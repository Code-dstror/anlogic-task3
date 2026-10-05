/* Optional RK3576 native SDK metadata query; no inference and no installation.
 * Compile only on the board against its already available rknn_api.h/librknnrt.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "rknn_api.h"

static int print_attr(rknn_context context, rknn_query_cmd command, uint32_t index,
                      const char *direction) {
    rknn_tensor_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.index = index;
    int ret = rknn_query(context, command, &attr, sizeof(attr));
    printf("query_%s_%u_return=%d\n", direction, index, ret);
    if (ret != RKNN_SUCC) return ret;
    printf("%s[%u] name=%s n_dims=%u dims=", direction, index, attr.name, attr.n_dims);
    for (uint32_t i = 0; i < attr.n_dims && i < RKNN_MAX_DIMS; ++i)
        printf("%s%u", i ? "," : "", attr.dims[i]);
    printf(" fmt=%d type=%d qnt_type=%d zp=%d scale=%.9g size=%u size_with_stride=%u\n",
           (int)attr.fmt, (int)attr.type, (int)attr.qnt_type, attr.zp,
           attr.scale, attr.size, attr.size_with_stride);
    return RKNN_SUCC;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s model.rknn\n", argv[0]);
        return 2;
    }
    rknn_context context = 0;
    int ret = rknn_init(&context, argv[1], 0, 0, NULL);
    printf("rknn_init_return=%d\n", ret);
    if (ret != RKNN_SUCC) return 1;

    rknn_sdk_version version;
    memset(&version, 0, sizeof(version));
    ret = rknn_query(context, RKNN_QUERY_SDK_VERSION, &version, sizeof(version));
    printf("sdk_version_query_return=%d\n", ret);
    if (ret == RKNN_SUCC)
        printf("api_version=%s driver_version=%s\n", version.api_version, version.drv_version);

    rknn_input_output_num count;
    memset(&count, 0, sizeof(count));
    ret = rknn_query(context, RKNN_QUERY_IN_OUT_NUM, &count, sizeof(count));
    printf("input_output_count_query_return=%d\n", ret);
    if (ret != RKNN_SUCC || count.n_input > 32 || count.n_output > 32) {
        rknn_destroy(context);
        return 1;
    }
    printf("n_input=%u n_output=%u\n", count.n_input, count.n_output);
    for (uint32_t i = 0; i < count.n_input; ++i)
        if (print_attr(context, RKNN_QUERY_INPUT_ATTR, i, "input") != RKNN_SUCC) {
            rknn_destroy(context);
            return 1;
        }
    for (uint32_t i = 0; i < count.n_output; ++i)
        if (print_attr(context, RKNN_QUERY_OUTPUT_ATTR, i, "output") != RKNN_SUCC) {
            rknn_destroy(context);
            return 1;
        }
    printf("rknn_destroy_return=%d\n", rknn_destroy(context));
    return 0;
}
