# Sourced by the bootstrap scripts.
# read_hosts FILE: read an Ansible YAML inventory and print one "name<TAB>address<TAB>user<TAB>port" line per host.
# Looks at every "hosts:" block and reads ansible_host, ansible_user and ansible_port; other keys are ignored.
# Plain awk, no YAML library needed, so keep the block style shown in ansible/inventory/hosts.example.yml.
read_hosts() {
    awk '
        function fail(msg, line) { print FILENAME ":" (line ? line : NR) ": " msg > "/dev/stderr"; err = 1 }
        { sub(/[[:space:]]#.*$/, ""); sub(/^#.*$/, ""); sub(/[[:space:]]+$/, "") }
        /^[[:space:]]*$/ { next }
        {
            match($0, /^ */); ind = RLENGTH
            line = substr($0, ind + 1)
        }
        in_hosts && ind <= hosts_ind { in_hosts = 0 }
        line == "hosts:" { in_hosts = 1; hosts_ind = ind; host_ind = -1; host = ""; next }
        !in_hosts { next }
        {
            if (host_ind < 0) host_ind = ind
            if (ind == host_ind) {
                # A host entry: "lab1:"
                host = line; sub(/:.*/, "", host)
                if (line != host ":") { fail("expected \"" host ":\" on its own line"); host = ""; next }
                if (!(host in seen)) { seen[host] = 1; order[++n] = host; start[host] = NR }
                next
            }
            if (host == "" || !match(line, /^[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/)) next
            key = line; sub(/:.*/, "", key)
            val = substr(line, RLENGTH + 1); gsub(/^["\047]|["\047]$/, "", val)
            if (key == "ansible_host") addr[host] = val
            else if (key == "ansible_user") user[host] = val
            else if (key == "ansible_port") port[host] = val
        }
        END {
            for (i = 1; i <= n; i++) {
                h = order[i]; a = (h in addr) ? addr[h] : h; p = (h in port) ? port[h] : 22
                if (h !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) fail("invalid host name \"" h "\" (use letters, digits, ., _, -)", start[h])
                else if (user[h] == "") fail(h ": ansible_user is required", start[h])
                else if (p !~ /^[0-9]+$/ || p + 0 < 1 || p + 0 > 65535) fail(h ": ansible_port must be 1-65535", start[h])
                else print h "\t" a "\t" user[h] "\t" p
            }
            if (!n && !err) fail("no hosts defined")
            exit err
        }
    ' "$1"
}
