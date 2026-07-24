# Nitrokey HSM 2 Initialization and Redundancy

This runbook covers Linux workstation setup, initializing two Nitrokey HSM 2
devices with a shared Device Key Encryption Key (DKEK), and verifying that a key
can be wrapped on one device and unwrapped on the other.

It does **not** create the offline root CA certificate. After both devices are
initialized and the smoke test passes, continue with the
[Offline CA ceremony runbook](ceremony-runbook.md).

Related: [ADR-0001](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0001-nitrokey-hsm2-offline-ca.md).

## Security rules

- Never commit SO-PINs, user PINs, DKEK share passwords, or `.pbe` / wrapped-key
  files to git.
- Prefer a dedicated Linux ceremony host. Disconnect networking before any real
  root CA ceremony (this init/smoke path may be done while still online).
- Clear shell history after commands that embed PINs on the command line.
- Private keys must never leave the HSM except as DKEK-wrapped blobs between
  devices that share the same DKEK.

## Secrets to prepare

| Secret | Format | Notes |
| ------ | ------ | ----- |
| SO-PIN | Exactly 16 hex digits (`0-9a-f`) | Per device; may differ between A and B |
| User PIN | 6–16 decimal digits | Per device; may differ between A and B |
| DKEK share password | Strong passphrase | Protects `dkek-share-1.pbe`; shared across both devices |

Different SO-PIN / user PIN values on A vs B are fine. Redundancy depends on the
**same DKEK**, not matching PINs.

Factory defaults (reference only, do not keep them): SO-PIN
`3537363231383830`, user PIN `648219`.

Generate strong values offline, for example:

```sh
openssl rand -hex 8
python3 -c 'import secrets; print("".join(str(secrets.randbelow(10)) for _ in range(8)))'
openssl rand -base64 24
```

Write them down and store them with the same custody model as the devices.

## Linux workstation setup

### Packages (Debian / Ubuntu)

```sh
sudo apt update
sudo apt install opensc opensc-pkcs11 openssl pcscd libccid pcsc-tools \
  libengine-pkcs11-openssl
sudo systemctl enable --now pcscd
```

`libengine-pkcs11-openssl` is required later for HSM-backed root self-sign /
signing in [ceremony-runbook.md](ceremony-runbook.md); installing it here avoids
a mid-ceremony package fetch on an offline host.

### PKCS#11 module

```sh
export PKCS11_MODULE=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
# Fedora / some installs: /usr/lib64/opensc-pkcs11.so
```

### Polkit access over SSH

Ubuntu’s `pcscd` allows only an active local seat by default. SSH sessions get
`Access denied` / “No smart card readers found” even when `lsusb` shows the
Nitrokey.

Allow the ceremony operator (example user `fred`):

```sh
sudo tee /etc/polkit-1/rules.d/99-pcscd-fred.rules >/dev/null <<'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id == "org.debian.pcsc-lite.access_pcsc" ||
         action.id == "org.debian.pcsc-lite.access_card") &&
        subject.user == "fred") {
        return polkit.Result.YES;
    }
});
EOF
sudo systemctl restart pcscd
```

On a dedicated offline box, an alternative is
`PCSCD_ARGS=--disable-polkit` in `/etc/default/pcscd`, then restart `pcscd`.

### Verify detection

Plug in one device at a time:

```sh
lsusb | grep -i nitro
opensc-tool --list-readers
pkcs11-tool --module "$PKCS11_MODULE" --list-slots
sc-hsm-tool
```

`pcsc_scan` watches forever; Ctrl+C after you see the reader. Prefer the
one-shot tools above.

Record non-secret inventory (example from lab devices):

| Device | USB / OpenSC serial | Intended label |
| ------ | ------------------- | -------------- |
| A | `DENK0500016` | `MyCloud-Offline-A` |
| B | `DENK0403732` | `MyCloud-Offline-B` |

A brand-new device reports that it has never been initialized.

## Initialize both devices with a shared DKEK

Work in a directory outside the git tree (example: `~/hsm-ceremony`).

### 1. Create one DKEK share

```sh
mkdir -p ~/hsm-ceremony && cd ~/hsm-ceremony
sc-hsm-tool --create-dkek-share dkek-share-1.pbe
```

Enter the DKEK password when prompted. Keep `dkek-share-1.pbe` and its password
with HSM recovery material — not in this repository.

### 2. Initialize the plugged-in device

```sh
sc-hsm-tool --initialize \
  --so-pin 'YOUR_SO_PIN' \
  --pin 'YOUR_USER_PIN' \
  --dkek-shares 1 \
  --label 'MyCloud-Offline-B'
```

Use `--label 'MyCloud-Offline-A'` when initializing device A.

`--initialize` erases the device. Confirm you have the correct stick inserted.

### 3. Import the DKEK share

```sh
sc-hsm-tool --import-dkek-share dkek-share-1.pbe
```

Record the **DKEK key check value (KCV)** printed by the tool.

### 4. Repeat on the other device

Unplug the first device, plug the second, repeat initialize + import with the
**same** `dkek-share-1.pbe`. The KCV must match.

Confirm with:

```sh
sc-hsm-tool
```

Both devices should show `DKEK shares : 1` and the same KCV.

## Key reference vs PKCS#11 ID (important)

`pkcs11-tool --id` is a PKCS#11 **CKA_ID** (hex). `sc-hsm-tool --key-reference`
is the SmartCard-HSM **Key ref** (decimal). They are often **not** equal.

Wrong reference produces:

```text
sc_card_ctl(*, SC_CARDCTL_SC_HSM_WRAP_KEY, *) failed with Data object not found
```

Always resolve the Key ref before wrap/unwrap:

```sh
pkcs15-tool --list-keys
```

Example output:

```text
Private RSA Key [smoke-test]
	Key ref        : 1 (0x01)
	ID             : 10
```

Wrap with `--key-reference 1`, not `10` or `16`.

## DKEK smoke test (wrap A → unwrap B)

Use a throwaway key. Do this before the real root key exists so recovery is
proven early.

### On device A

```sh
cd ~/hsm-ceremony
export PKCS11_MODULE=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so

pkcs11-tool --module "$PKCS11_MODULE" --login --pin 'YOUR_USER_PIN' \
  --keypairgen --key-type rsa:2048 --id 01 --label 'smoke-test'

pkcs15-tool --list-keys
# Note Key ref (often 1 for the first key)

sc-hsm-tool --wrap-key smoke-wrap.bin --key-reference 1 --pin 'YOUR_USER_PIN'
ls -l smoke-wrap.bin
```

Prefer `--id 01` so CKA_ID and Key ref stay easy to reason about; still confirm
with `pkcs15-tool`.

### On device B

```sh
sc-hsm-tool --unwrap-key smoke-wrap.bin --key-reference 1 --pin 'YOUR_USER_PIN' --force
pkcs11-tool --module "$PKCS11_MODULE" --login --pin 'YOUR_USER_PIN' --list-objects
```

Success looks like:

```text
Wrapped key contains:
  Key blob
  Private Key Description (PRKD)
  Certificate
Key successfully imported
```

### Cleanup

Delete the smoke key on **both** devices and remove the wrap file:

```sh
pkcs11-tool --module "$PKCS11_MODULE" --login --pin 'YOUR_USER_PIN' \
  --delete-object --type privkey --id 01
pkcs11-tool --module "$PKCS11_MODULE" --login --pin 'YOUR_USER_PIN' \
  --delete-object --type pubkey --id 01
rm -f ~/hsm-ceremony/smoke-wrap.bin
```

Adjust `--id` if you used a different CKA_ID. Clear shell history after PIN use.

## Recovering a key onto a replacement device

1. Initialize the replacement with the same SO-PIN/PIN policy and
   `--dkek-shares 1`.
2. Import the same `dkek-share-1.pbe` (KCV must match the surviving device).
3. Unwrap each wrapped key blob with `sc-hsm-tool --unwrap-key` using a free
   `--key-reference`.

Without a DKEK (or without the share file + password), keys cannot be moved to
another stick.

## After initialization

Proceed to root CA creation and intermediate signing in
[ceremony-runbook.md](ceremony-runbook.md). Keep both HSMs, the DKEK share, and
PIN material under documented custody.
