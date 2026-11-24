// libglsec: Security for GRID Legends. Re-exports libvxsec (VXpro: Security + the macOS-only TLS calls) and adds the
// legacy file-keychain calls: nothing is ever found and nothing is stored (online logins are out of scope).
#include <stdint.h>
#include "glcommon.h"

typedef int32_t OSStatus_;
enum { errSecItemNotFound_ = -25300, errSecUnimplemented_ = -4 };

OSStatus_ SecKeychainFindGenericPassword(const void *kc, uint32_t sl, const char *s, uint32_t al, const char *a,
                                         uint32_t *len, void **data, void **item) {
    (void)kc; (void)sl; (void)s; (void)al; (void)a;
    if (len) *len = 0;
    if (data) *data = NULL;
    if (item) *item = NULL;
    return errSecItemNotFound_;
}
OSStatus_ SecKeychainAddGenericPassword(const void *kc, uint32_t sl, const char *s, uint32_t al, const char *a,
                                        uint32_t len, const void *data, void **item) {
    (void)kc; (void)sl; (void)s; (void)al; (void)a; (void)len; (void)data;
    if (item) *item = NULL;
    gl_log_once("Security: SecKeychainAddGenericPassword -> errSecUnimplemented");
    return errSecUnimplemented_;
}
OSStatus_ SecKeychainItemCopyAttributesAndData(const void *item, void *info, void *cls, void **attrs, uint32_t *len, void **data) {
    (void)item; (void)info; (void)cls;
    if (attrs) *attrs = NULL;
    if (len) *len = 0;
    if (data) *data = NULL;
    return errSecItemNotFound_;
}
OSStatus_ SecKeychainItemFreeAttributesAndData(void *attrs, void *data) { (void)attrs; (void)data; return 0; }
OSStatus_ SecKeychainItemModifyContent(void *item, const void *attrs, uint32_t len, const void *data) {
    (void)item; (void)attrs; (void)len; (void)data; return errSecUnimplemented_;
}
OSStatus_ SecKeychainItemDelete(void *item) { (void)item; return errSecItemNotFound_; }
OSStatus_ SecCertificateAddToKeychain(const void *cert, const void *kc) { (void)cert; (void)kc; return errSecUnimplemented_; }
OSStatus_ SecTrustSettingsSetTrustSettings(const void *cert, uint32_t domain, const void *settings) {
    (void)cert; (void)domain; (void)settings; return errSecUnimplemented_;
}
