/*
 * Various things to allow source files from postgresql code to be
 * used in pgbouncer.  pgbouncer's system.h needs to be included
 * before this.
 */

/* from c.h */

#include <string.h>
#include <usual/ctype.h>

#define int8 int8_t
#define uint8 uint8_t
#define uint16 uint16_t
#define uint32 uint32_t

#define lengthof(array) (sizeof (array) / sizeof ((array)[0]))
#define pg_hton32(x) htobe32(x)

#define pg_attribute_noreturn() _NORETURN

#define HIGHBIT					(0x80)
#define IS_HIGHBIT_SET(ch)		((unsigned char)(ch) & HIGHBIT)


#ifdef HAVE_OPENSSL
/* Use OpenSSL EVP interface for FIPS compliance */
#include <openssl/evp.h>
#define pg_sha256_ctx EVP_MD_CTX *
#define PG_SHA256_BLOCK_LENGTH 64
#define PG_SHA256_DIGEST_LENGTH 32
#define pg_sha256_init(ctx) do { \
    *(ctx) = EVP_MD_CTX_new(); \
    EVP_DigestInit_ex(*(ctx), EVP_sha256(), NULL); \
} while(0)
#define pg_sha256_update(ctx, data, len) EVP_DigestUpdate(*(ctx), data, len)
#define pg_sha256_final(ctx, dst) do { \
    unsigned int _len; \
    EVP_DigestFinal_ex(*(ctx), dst, &_len); \
    EVP_MD_CTX_free(*(ctx)); \
} while(0)
#else
/* sha2.h compat */
#define pg_sha256_ctx struct sha256_ctx
#define PG_SHA256_BLOCK_LENGTH SHA256_BLOCK_SIZE
#define PG_SHA256_DIGEST_LENGTH SHA256_DIGEST_LENGTH
#define pg_sha256_init(ctx) sha256_reset(ctx)
#define pg_sha256_update(ctx, data, len) sha256_update(ctx, data, len)
#define pg_sha256_final(ctx, dst) sha256_final(ctx, dst)
#endif


/* define this to use non-server code paths */
#define FRONTEND


/*
 * PostgreSQL project wrapper for strlcpy/strlcat.
 */

#ifndef HAVE_STRLCPY
extern size_t strlcpy(char *dst, const char *src, size_t siz);
#endif

#ifndef HAVE_STRLCAT
extern size_t strlcat(char *dst, const char *src, size_t siz);
#endif 