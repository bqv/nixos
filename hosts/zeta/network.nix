{ config, lib, pkgs, hosts, ... }:

let
  wanInterface = "eno1";
  vlanInterface = idx: "fo${toString idx}";
  v6Block = rec {
    addr = "${block}1";
    block = "${hosts.ipv6.zeta.prefix}:";
    subnet = "${block}/${toString prefix}";
    duid = hosts.duid.${addr};
    prefix = hosts.ipv6.zeta.length;
  };
  v6Subnets = hosts.duid;
in {
  imports = [
    ../../containers/sandbox.nix   # 10. 1.0.x
    ../../containers/secure.nix    # 10. 2.0.x
   #../../containers/certmon.nix   # 10. 3.0.x
    ../../containers/authority.nix # 10. 4.0.x
    ../../containers/search.nix    # 10. 5.0.x
    ../../containers/mastodon.nix  # 10. 6.0.x
    ../../containers/matrix.nix    # 10. 7.0.x
    ../../containers/hydroxide.nix # 10. 8.0.x
    ../../containers/anki.nix      # 10. 9.0.x
    ../../containers/klaus.nix     # 10.10.0.x
    ../../containers/jellyfin.nix  # 10.11.0.x
  ];

  isolation = {
    makeHostAddress = { id, ... }: "10.${toString id}.0.1";
    makeHostAddress6 = { id, ... }: "2001:bc8:3de4::${toString id}:1";
    makeLocalAddress = { id, ... }: "10.${toString id}.0.2";
    makeLocalAddress6 = { id, ... }: "2001:bc8:3de4::${toString id}:2";
    scopes.klaus.id = 10;
  };

  networking.interfaces.${wanInterface} = {
    ipv4.addresses = [
      { address = hosts.ipv4.zeta; prefixLength = 24; }
    ];
    ipv6.addresses = let
      morph = block: { address = block.addr; prefixLength = block.length; };
      transform = addr: { address = addr; prefixLength = v6Subnets.${addr}.length; };
    in
      [ (morph v6Block) ] ++ map transform (builtins.attrNames v6Subnets);
    ipv6.routes = [
      { address = hosts.ipv6.r-zeta; prefixLength = 128; }
    ];
  };
  networking.vlans.${vlanInterface 1} = {
    id = 0;
    interface = wanInterface;
  };
  networking.interfaces.${vlanInterface 1} = {
    ipv4.addresses = [
      { address = hosts.ipv4.zeta-alt; prefixLength = 32; }
    ];
  };

  networking.nat.enable = true;
  networking.nat.internalInterfaces = ["ve-+"];
  networking.nat.externalInterface = wanInterface;
  systemd.services.nat.path = with pkgs; lib.mkForce [
    iptables-nftables-compat coreutils
  ];

  networking.firewall.enable = false;
  networking.nftables = {
    enable = true;
    ruleset = ''
      table inet filter {
        # Block all incomming connections traffic except SSH and "ping".
        chain input {
          type filter hook input priority 0;

          # accept any localhost traffic
          iifname lo accept

          # accept traffic originated from us
          ct state {established, related} accept

          # ICMP
          # routers may also want: mld-listener-query, nd-router-solicit
          ip6 nexthdr icmpv6 icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept
          ip protocol icmp icmp type { destination-unreachable, router-advertisement, time-exceeded, parameter-problem } accept

          # allow "ping"
          ip6 nexthdr icmpv6 icmpv6 type echo-request accept
          ip protocol icmp icmp type echo-request accept

          # accept SSH connections (required for a server)
          tcp dport 22 accept

          # accept SSL connections
          tcp dport 80 accept
          tcp dport 443 accept

          # restrict imap and smtp to vpn
          ip saddr 10.0.0.0/24 accept
          tcp dport { 1143 } drop
          tcp dport { 1025 } drop

          tcp dport 4004 accept
          tcp dport 5432 accept
          tcp dport 8090 accept
          tcp dport 8448 accept
          tcp dport 22000 accept
          tcp dport 25565 accept
          udp dport 5353 accept
          udp dport 21027 accept
          udp dport 25565 accept
          udp dport 51820 accept
          udp dport 60000-61000 accept
          udp dport 60000-61000 accept

          # count and drop any other traffic
          #counter drop
          counter accept
        }

        # Allow all outgoing connections.
        chain output {
          type filter hook output priority 0;
          accept
        }

        chain forward {
          type filter hook forward priority 0;
          accept
        }
      }
    '';
  };

  networking.wireguard.interfaces.wg0 = {
    postSetup = let
      wanInterface = vlanInterface 1;
      nat = "${pkgs.iptables}/bin/iptables -w -t nat";
      proto = proto: "-p ${proto} -m ${proto}";
      icmp-echo = "--icmp-type 8";
      from-failover = "-d ${hosts.ipv4.zeta-alt}";
      to-delta = "--to-destination ${hosts.wireguard.delta}";
      lanInterface = "wg0";
    in ''
      # Enable packet forwarding to/from the target for established/related connections
     #iptables -A FORWARD -i ${wanInterface} -o ${lanInterface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
     #iptables -A FORWARD -i ${lanInterface} -o ${wanInterface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

      # Enable masquerade on the target
     #${nat} -A nixos-nat-post -o ${lanInterface} -s ${hosts.wireguard.delta} -j MASQUERADE

      # Forward from source to target
     #${nat} -A nixos-nat-pre  -i ${wanInterface} ${proto "tcp" } ${from-failover} -j DNAT ${to-delta}

      # Hmm.
     #${nat} -A nixos-nat-pre  -i ${wanInterface} ${proto "icmp"} ${from-failover} -j DNAT ${to-delta} ${icmp-echo}
     #${nat} -A nixos-nat-pre  -i ${wanInterface} ${proto "udp" } ${from-failover} -j DNAT ${to-delta}
    '';
  };

  networking.defaultGateway = hosts.ipv4.r-zeta;
  networking.nameservers = [ "9.9.9.9" ];

  environment.etc.dhclient6 = {
    target = "dhcp/dhclient6.conf";
    text = ''
      interface "${wanInterface}" {
         send dhcp6.client-id ${v6Block.duid};
      }
    '';
  };

  networking.enableIPv6 = true;
  systemd.services.dhclient = {
    description = "Client for sending IPv6 DUID";
    wants = [ "network-link-${wanInterface}.service" ];
    after = [ "network-link-${wanInterface}.service" ];
    before = [ "network-addresses-${wanInterface}.service" ];
    serviceConfig = {
      Type = "forking";
    };
    script = with config.environment; "${pkgs.dhcp}/sbin/dhclient -cf /etc/${etc.dhclient6.target} -6 -P -v ${wanInterface}";
    wantedBy = [ "network.target" ];
  };
  systemd.services."network-addresses-${wanInterface}" = {
    after = [ "dhclient.service" ];
    partOf = [ "dhclient.service" ];
  };
}
