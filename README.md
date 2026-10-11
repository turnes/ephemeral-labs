# ephemeral-Labs-KVM
Ephemeral Labs with KVM

## Installing KVM (Ubuntu 26.04)

Turn on virtualization (VT-x/AMD-V) in BIOS/UEFI first.

### Get the repo

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/turnes/ephemeral-labs.git
cd ephemeral-labs
```

Then pick one option.

### Bootstrap script

```bash
./boostrap/install-kvm-ubuntu.sh --check-only
sudo ./boostrap/install-kvm-ubuntu.sh            # add --with-gui for virt-manager
```

### Ansible

```bash
sudo apt update && sudo apt install -y ansible-core
cd ansible
ansible-playbook -i inventory.ini install-kvm.yml -K   # add -e kvm_with_gui=true for virt-manager
```

### Verify

Log out and back in so the group changes apply, then run:

```bash
kvm-ok
virsh -c qemu:///system list --all
```
