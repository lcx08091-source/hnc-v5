/*
 * HNC hotfix20.2 - optional C helper for hnc_json.
 *
 * Scope is intentionally conservative:
 *   hnc_json_c validate <file>
 *   hnc_json_c get-top <file> <key>
 *   hnc_json_c version
 *
 * Runtime writes still stay in the shell frontend. bin/hnc_json may delegate
 * read-only validate/get-top calls to this helper when bin/hnc_json_c exists,
 * and falls back to shell implementation otherwise.
 */
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *read_file(const char *path, size_t *out_len) {
    FILE *fp = fopen(path, "rb");
    if (!fp) return NULL;
    if (fseek(fp, 0, SEEK_END) != 0) { fclose(fp); return NULL; }
    long n = ftell(fp);
    if (n < 0) { fclose(fp); return NULL; }
    if (fseek(fp, 0, SEEK_SET) != 0) { fclose(fp); return NULL; }
    char *buf = (char *)malloc((size_t)n + 1);
    if (!buf) { fclose(fp); errno = ENOMEM; return NULL; }
    size_t got = fread(buf, 1, (size_t)n, fp);
    fclose(fp);
    if (got != (size_t)n) { free(buf); return NULL; }
    buf[got] = '\0';
    if (out_len) *out_len = got;
    return buf;
}

static int validate_json_text(const char *s, size_t n) {
    int in_string = 0;
    int esc = 0;
    char stack[1024];
    int sp = 0;
    int saw = 0;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if (in_string) {
            if (esc) { esc = 0; continue; }
            if (c == '\\') { esc = 1; continue; }
            if (c == '"') { in_string = 0; continue; }
            if (c < 0x20) return 1;
            continue;
        }
        if (isspace(c)) continue;
        saw = 1;
        if (c == '"') { in_string = 1; continue; }
        if (c == '{' || c == '[') {
            if (sp >= (int)sizeof(stack)) return 1;
            stack[sp++] = (char)c;
            continue;
        }
        if (c == '}' || c == ']') {
            if (sp <= 0) return 1;
            char open = stack[--sp];
            if ((open == '{' && c != '}') || (open == '[' && c != ']')) return 1;
            continue;
        }
    }
    return (!saw || in_string || esc || sp != 0) ? 1 : 0;
}

static size_t skip_ws(const char *s, size_t n, size_t i) {
    while (i < n && isspace((unsigned char)s[i])) i++;
    return i;
}

static int parse_string_key(const char *s, size_t n, size_t *io, char *out, size_t out_sz) {
    size_t i = *io;
    size_t k = 0;
    if (i >= n || s[i] != '"') return 0;
    i++;
    while (i < n) {
        unsigned char c = (unsigned char)s[i++];
        if (c == '"') { out[k < out_sz ? k : out_sz - 1] = '\0'; *io = i; return 1; }
        if (c == '\\') {
            if (i >= n) return 0;
            c = (unsigned char)s[i++];
            switch (c) {
                case '"': case '\\': case '/': break;
                case 'b': c = '\b'; break;
                case 'f': c = '\f'; break;
                case 'n': c = '\n'; break;
                case 'r': c = '\r'; break;
                case 't': c = '\t'; break;
                case 'u':
                    /* Keys used by HNC are ASCII identifiers. Preserve a placeholder
                     * for unicode escapes instead of implementing full UTF-8 decode. */
                    if (i + 4 > n) return 0;
                    i += 4;
                    c = '?';
                    break;
                default: return 0;
            }
        }
        if (k + 1 < out_sz) out[k++] = (char)c;
    }
    return 0;
}

static int value_end(const char *s, size_t n, size_t start, size_t *end_out) {
    int in_string = 0;
    int esc = 0;
    int depth = 0;
    for (size_t i = start; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if (in_string) {
            if (esc) { esc = 0; continue; }
            if (c == '\\') { esc = 1; continue; }
            if (c == '"') { in_string = 0; continue; }
            continue;
        }
        if (c == '"') { in_string = 1; continue; }
        if (c == '{' || c == '[') { depth++; continue; }
        if (c == '}' || c == ']') {
            if (depth == 0) { *end_out = i; return 1; }
            depth--;
            continue;
        }
        if (c == ',' && depth == 0) { *end_out = i; return 1; }
    }
    *end_out = n;
    return 1;
}

static int get_top(const char *path, const char *key) {
    size_t n = 0;
    char *s = read_file(path, &n);
    if (!s) { perror("open"); return 2; }
    if (validate_json_text(s, n) != 0) { free(s); return 2; }
    size_t i = skip_ws(s, n, 0);
    if (i >= n || s[i] != '{') { free(s); return 2; }
    i++;
    for (;;) {
        i = skip_ws(s, n, i);
        if (i >= n) { free(s); return 2; }
        if (s[i] == '}') { free(s); return 3; }
        if (s[i] == ',') { i++; continue; }
        char kbuf[256];
        if (!parse_string_key(s, n, &i, kbuf, sizeof(kbuf))) { free(s); return 2; }
        i = skip_ws(s, n, i);
        if (i >= n || s[i] != ':') { free(s); return 2; }
        i = skip_ws(s, n, i + 1);
        size_t ve = i;
        if (!value_end(s, n, i, &ve)) { free(s); return 2; }
        if (strcmp(kbuf, key) == 0) {
            while (ve > i && isspace((unsigned char)s[ve - 1])) ve--;
            fwrite(s + i, 1, ve - i, stdout);
            fputc('\n', stdout);
            free(s);
            return 0;
        }
        i = ve;
    }
}

int main(int argc, char **argv) {
    if (argc >= 2 && strcmp(argv[1], "version") == 0) {
        puts("hnc_json_c hotfix20.2 read-only helper");
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "validate") == 0) {
        size_t n = 0;
        char *s = read_file(argv[2], &n);
        if (!s) { perror("open"); return 2; }
        int rc = validate_json_text(s, n);
        free(s);
        return rc;
    }
    if (argc == 4 && (strcmp(argv[1], "get-top") == 0 || strcmp(argv[1], "get") == 0)) {
        return get_top(argv[2], argv[3]);
    }
    fprintf(stderr, "usage: %s validate <file> | get-top <file> <key> | version\n", argv[0]);
    return 2;
}
