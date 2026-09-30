#include "P12Normalizer.h"
#include <stdlib.h>
#include <string.h>

#if __has_include(<openssl/pkcs12.h>)
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pkcs12.h>
#include <openssl/provider.h>
#include <openssl/x509.h>

namespace {

struct Found {
    EVP_PKEY *key = nullptr;
    STACK_OF(X509) *certs = sk_X509_new_null();
    ~Found() {
        EVP_PKEY_free(key);
        sk_X509_pop_free(certs, X509_free);
    }
};

void collect(const STACK_OF(PKCS12_SAFEBAG) *bags, const char *pass, Found &found) {
    for (int i = 0; i < sk_PKCS12_SAFEBAG_num(bags); i++) {
        const PKCS12_SAFEBAG *bag = sk_PKCS12_SAFEBAG_value(bags, i);
        switch (PKCS12_SAFEBAG_get_nid(bag)) {
        case NID_keyBag:
            if (!found.key) found.key = EVP_PKCS82PKEY(PKCS12_SAFEBAG_get0_p8inf(bag));
            break;
        case NID_pkcs8ShroudedKeyBag:
            if (!found.key) {
                PKCS8_PRIV_KEY_INFO *p8 = PKCS12_decrypt_skey(bag, pass, -1);
                if (p8) {
                    found.key = EVP_PKCS82PKEY(p8);
                    PKCS8_PRIV_KEY_INFO_free(p8);
                }
            }
            break;
        case NID_certBag:
            if (PKCS12_SAFEBAG_get_bag_nid(bag) == NID_x509Certificate) {
                if (X509 *cert = PKCS12_SAFEBAG_get1_cert(bag)) sk_X509_push(found.certs, cert);
            }
            break;
        case NID_safeContentsBag:
            collect(PKCS12_SAFEBAG_get0_safes(bag), pass, found);
            break;
        default:
            break;
        }
    }
}

}  // namespace

extern "C" OrbitP12Status orbit_p12_normalize(const uint8_t *data, size_t length, const char *password,
                                              uint8_t **out, size_t *outLength) {
    // Default provider for PBE-SHA1-3DES/AES; legacy (if bundled) for RC2-encrypted inputs.
    static bool providers = [] {
        OSSL_PROVIDER_load(nullptr, "default");
        OSSL_PROVIDER_load(nullptr, "legacy");
        ERR_clear_error();
        return true;
    }();
    (void)providers;

    *out = nullptr;
    *outLength = 0;
    const char *pass = password ? password : "";

    const unsigned char *p = data;
    PKCS12 *p12 = d2i_PKCS12(nullptr, &p, (long)length);
    if (!p12) { ERR_clear_error(); return ORBIT_P12_INVALID; }

    if (PKCS12_mac_present(p12) && !PKCS12_verify_mac(p12, pass, -1)) {
        PKCS12_free(p12);
        ERR_clear_error();
        return ORBIT_P12_WRONG_PASSWORD;
    }

    Found found;
    if (STACK_OF(PKCS7) *safes = PKCS12_unpack_authsafes(p12)) {
        for (int i = 0; i < sk_PKCS7_num(safes); i++) {
            PKCS7 *p7 = sk_PKCS7_value(safes, i);
            STACK_OF(PKCS12_SAFEBAG) *bags = nullptr;
            switch (OBJ_obj2nid(p7->type)) {
            case NID_pkcs7_data: bags = PKCS12_unpack_p7data(p7); break;
            case NID_pkcs7_encrypted: bags = PKCS12_unpack_p7encdata(p7, pass, -1); break;
            default: break;
            }
            if (bags) {
                collect(bags, pass, found);
                sk_PKCS12_SAFEBAG_pop_free(bags, PKCS12_SAFEBAG_free);
            }
        }
        sk_PKCS7_pop_free(safes, PKCS7_free);
    }
    PKCS12_free(p12);

    X509 *cert = nullptr;
    for (int i = 0; found.key && i < sk_X509_num(found.certs); i++) {
        X509 *c = sk_X509_value(found.certs, i);
        if (X509_check_private_key(c, found.key)) { cert = c; break; }
    }
    if (!found.key || !cert) {
        ERR_clear_error();
        // Without a MAC the password is only checked by decryption, so a failure
        // here most likely means it was wrong.
        return ORBIT_P12_WRONG_PASSWORD;
    }

    PKCS12 *normalized = PKCS12_create(pass, nullptr, found.key, cert, nullptr,
                                       NID_pbe_WithSHA1And3_Key_TripleDES_CBC,
                                       NID_pbe_WithSHA1And3_Key_TripleDES_CBC,
                                       2048, -1, 0);   // MAC added below: SHA-1, not OpenSSL 3's SHA-256
    if (!normalized || !PKCS12_set_mac(normalized, pass, -1, nullptr, 0, 2048, EVP_sha1())) {
        PKCS12_free(normalized);
        ERR_clear_error();
        return ORBIT_P12_INVALID;
    }

    unsigned char *der = nullptr;
    int derLength = i2d_PKCS12(normalized, &der);
    PKCS12_free(normalized);
    if (derLength <= 0) { ERR_clear_error(); return ORBIT_P12_INVALID; }

    *out = (uint8_t *)malloc((size_t)derLength);
    memcpy(*out, der, (size_t)derLength);
    *outLength = (size_t)derLength;
    OPENSSL_free(der);
    return ORBIT_P12_OK;
}

#else

extern "C" OrbitP12Status orbit_p12_normalize(const uint8_t *, size_t, const char *, uint8_t **out, size_t *outLength) {
    *out = nullptr;
    *outLength = 0;
    return ORBIT_P12_UNAVAILABLE;
}

#endif
