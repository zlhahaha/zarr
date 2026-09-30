#include <stdint.h>
#include <time.h>

int64_t zarr_s3_unix_seconds(void) {
  time_t now = time(NULL);
  return now == (time_t)-1 ? -1 : (int64_t)now;
}
