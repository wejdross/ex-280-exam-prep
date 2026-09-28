# practice-scratch

Files I wrote by hand on the CRC cluster while drilling, outside the numbered topics.
They are kept as-is (some are live `oc get -o yaml` dumps, so they carry UIDs and
`resourceVersion`). Strip `metadata.uid`, `resourceVersion` and `creationTimestamp`
before applying.

| File | What |
|---|---|
| `htpasswd.conf` | two-user htpasswd file (`alice`, `bob`), bcrypt hashes |
| `oauth.yaml` | `oauth/cluster` with **two** HTPasswd identity providers, dumped from the cluster |
| `passthrough.yaml` | nginx on 8443 serving its own cert; the backend for a passthrough Route |
| `route.yaml` | edge-terminated Route with an inline self-signed cert and key for `*.apps-crc.testing` |

The private key in `route.yaml` is a throwaway self-signed one for a CRC-only hostname.
