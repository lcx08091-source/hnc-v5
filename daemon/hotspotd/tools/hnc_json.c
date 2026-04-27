/*
 * HNC hotfix18.9 - hnc_json C tool prototype.
 *
 * This file is intentionally small and self-contained. It is not wired into
 * the main build yet; the runtime CLI in bin/hnc_json is the safe bootstrap
 * frontend. The next JSON-unification phase can replace the shell frontend
 * with this compiled tool after device-side build validation.
 *
 * Current compiled prototype supports:
 *   hnc_json_c validate <file>
 *   hnc_json_c version
 *
 * Future planned commands:
 *   get-top, set-top, set-device, del-device, list-backups.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int validate_json_stream(FILE *fp) {
    int c;
    int in_string = 0;
    int esc = 0;
    int depth = 0;
    int saw = 0;

    while ((c = fgetc(fp)) != EOF) {
        saw = 1;
        if (in_string) {
            if (esc) {
                esc = 0;
                continue;
            }
            if (c == '\\') {
                esc = 1;
                continue;
            }
            if (c == '"') {
                in_string = 0;
                continue;
            }
            if ((unsigned char)c < 0x20) return 1;
            continue;
        }
        if (c == '"') {
            in_string = 1;
            continue;
        }
        if (c == '{' || c == '[') {
            depth++;
            continue;
        }
        if (c == '}' || c == ']') {
            depth--;
            if (depth < 0) return 1;
            continue;
        }
    }
    if (!saw || in_string || esc || depth != 0) return 1;
    return 0;
}

int main(int argc, char **argv) {
    if (argc >= 2 && strcmp(argv[1], "version") == 0) {
        puts("hnc_json_c prototype hotfix18.9");
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "validate") == 0) {
        FILE *fp = fopen(argv[2], "rb");
        if (!fp) {
            perror("open");
            return 2;
        }
        int rc = validate_json_stream(fp);
        fclose(fp);
        return rc;
    }
    fprintf(stderr, "usage: %s validate <file> | version\n", argv[0]);
    return 2;
}
