/* OS high-water memory and monotonic time for the benchmark executable only.
 * Original instrumentation; not part of the Zarr library implementation. */
#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#endif
#include <stdint.h>
#if defined(_WIN32)
#include <windows.h>
#include <psapi.h>

int64_t zarr_bench_time_ns(void) {
  LARGE_INTEGER ticks, frequency;
  if (!QueryPerformanceCounter(&ticks) || !QueryPerformanceFrequency(&frequency))
    return -1;
  return (ticks.QuadPart / frequency.QuadPart) * 1000000000LL +
         (ticks.QuadPart % frequency.QuadPart) * 1000000000LL / frequency.QuadPart;
}

int64_t zarr_bench_peak_rss(void) {
  PROCESS_MEMORY_COUNTERS counters = {0};
  counters.cb = sizeof(counters);
  typedef BOOL (WINAPI *memory_info_fn)(HANDLE, PPROCESS_MEMORY_COUNTERS, DWORD);
  memory_info_fn query = (memory_info_fn)GetProcAddress(
      GetModuleHandleW(L"kernel32.dll"), "K32GetProcessMemoryInfo");
  if (!query || !query(GetCurrentProcess(), &counters, sizeof(counters))) return -1;
  return (int64_t)counters.PeakWorkingSetSize;
}
#else
#include <sys/resource.h>
#include <time.h>

int64_t zarr_bench_time_ns(void) {
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return -1;
  return (int64_t)value.tv_sec * 1000000000LL + value.tv_nsec;
}

int64_t zarr_bench_peak_rss(void) {
  struct rusage usage;
  if (getrusage(RUSAGE_SELF, &usage) != 0) return -1;
#if defined(__APPLE__)
  return (int64_t)usage.ru_maxrss;
#else
  return (int64_t)usage.ru_maxrss * 1024;
#endif
}
#endif
