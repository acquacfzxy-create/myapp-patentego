# Apple root certificates (public, not secrets)

`apple_client.js` verifies App Store signed data (transaction JWS, server notifications) against
Apple's public root CA certificates. Place the DER-encoded `.cer` files here before deploying, e.g.
`AppleRootCA-G3.cer` (and `AppleIncRootCertificate.cer`), downloaded by the maintainer from
https://www.apple.com/certificateauthority/ and checked against Apple's published fingerprints.

Without any `.cer`/`.der` file here every App Store verification fails closed
(`apple-root-certificates-missing`); the Play flow is unaffected.
