# Restricted HDR packet-boundary contract

The donor R2 shared-header/zero-lookahead functional adapter is retained in
this complete dual-camera merge. Its current contract, limitations, exact
production file changes and source-bound qualification are documented in
[`docs/HDR_FUNCTIONAL_PORT.md`](../../docs/HDR_FUNCTIONAL_PORT.md).

This adapter does not detect a physical D-PHY EoT. Only a supported ECC-good
continuation may follow a completed packet. A corrected zero FS0 at this
boundary requires a nonzero supported next header; a fresh SoT FS0 does not.
Rejected trail drains until the actual geared-valid gap. Missing image
payload or FE cannot become a successful member or pair.
