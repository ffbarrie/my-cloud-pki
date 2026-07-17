# Issuing CA

Configuration and assets for the online intermediate / issuing CA.

Until the HSM offline root is available, the issuing CA certificate can be signed
by the [bootstrap software root CA](../bootstrap/software-root-ca.md). After HSM
ceremonies exist, re-issue under the offline root and retire the bootstrap chain.
