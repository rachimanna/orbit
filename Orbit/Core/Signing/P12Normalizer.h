#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ORBIT_P12_OK = 0,
    ORBIT_P12_WRONG_PASSWORD = 1,
    ORBIT_P12_INVALID = 2,
    ORBIT_P12_UNAVAILABLE = 3,
} OrbitP12Status;

/// Re-packs any PKCS#12 that OpenSSL can read into the classic layout iOS
/// SecPKCS12Import and zsign both accept: shrouded key + cert, PBE-SHA1-3DES,
/// HMAC-SHA1 MAC, protected with `password`.
///
/// Needed because some producers emit containers iOS rejects — e.g. SideStore's
/// certificate export (CodeSignKit PKCS12Builder) writes a plain KeyBag with no
/// encryption and no MAC, and OpenSSL 3 defaults to PBES2/AES.
///
/// A file with a MAC must verify with `password`, otherwise ORBIT_P12_WRONG_PASSWORD.
/// On success `*out` is malloc'ed; release it with free().
OrbitP12Status orbit_p12_normalize(const uint8_t *data, size_t length, const char *password,
                                   uint8_t **out, size_t *outLength);

#ifdef __cplusplus
}
#endif
