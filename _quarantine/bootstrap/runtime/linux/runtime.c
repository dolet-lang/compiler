/*
 * Dolet Runtime Library for Linux
 * Provides POSIX-compliant implementations
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/time.h>
#include <time.h>

/* ============================================================================
 * Memory Management
 * ============================================================================ */

void* dsl_malloc(size_t size) {
    return malloc(size);
}

void dsl_free(void* ptr) {
    free(ptr);
}

void* dsl_realloc(void* ptr, size_t size) {
    return realloc(ptr, size);
}

/* ============================================================================
 * String Operations
 * ============================================================================ */

size_t dsl_strlen(const char* str) {
    return strlen(str);
}

char* dsl_strcpy(char* dest, const char* src) {
    return strcpy(dest, src);
}

char* dsl_strcat(char* dest, const char* src) {
    return strcat(dest, src);
}

/* ============================================================================
 * Type Conversions
 * ============================================================================ */

/* New explicit type conversion functions */

char* dsl_i8_to_string(int8_t value) {
    char* buffer = (char*)malloc(8);  // -128 to 127 (max 4 chars + sign + null)
    if (buffer) {
        snprintf(buffer, 8, "%d", (int)value);
    }
    return buffer;
}

char* dsl_i16_to_string(int16_t value) {
    char* buffer = (char*)malloc(16);  // -32768 to 32767 (max 6 chars + sign + null)
    if (buffer) {
        snprintf(buffer, 16, "%d", (int)value);
    }
    return buffer;
}

char* dsl_i32_to_string(int32_t value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        snprintf(buffer, 32, "%d", value);
    }
    return buffer;
}

char* dsl_i64_to_string(int64_t value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        snprintf(buffer, 32, "%ld", value);
    }
    return buffer;
}

char* dsl_u8_to_string(uint8_t value) {
    char* buffer = (char*)malloc(8);  // 0 to 255 (max 3 chars + null)
    if (buffer) {
        snprintf(buffer, 8, "%u", (unsigned int)value);
    }
    return buffer;
}

char* dsl_u16_to_string(uint16_t value) {
    char* buffer = (char*)malloc(16);  // 0 to 65535 (max 5 chars + null)
    if (buffer) {
        snprintf(buffer, 16, "%u", (unsigned int)value);
    }
    return buffer;
}

char* dsl_u32_to_string(uint32_t value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        snprintf(buffer, 32, "%u", value);
    }
    return buffer;
}

char* dsl_u64_to_string(uint64_t value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        snprintf(buffer, 32, "%lu", value);
    }
    return buffer;
}

char* dsl_f32_to_string(float value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        snprintf(buffer, 32, "%f", value);
    }
    return buffer;
}

char* dsl_f64_to_string(double value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        snprintf(buffer, 32, "%lf", value);
    }
    return buffer;
}

char* dsl_i128_to_string(void* value) {
    // Full i128 support using __int128 (GCC/Clang) or manual division
    #if defined(__SIZEOF_INT128__)
        __int128 val = *(__int128*)value;
        char* buffer = (char*)malloc(48);  // Enough for 128-bit number + sign + null
        if (!buffer) return NULL;
        
        // Handle negative numbers
        int is_negative = 0;
        unsigned __int128 uval;
        if (val < 0) {
            is_negative = 1;
            uval = -val;
        } else {
            uval = val;
        }
        
        // Convert to string (reverse order)
        char temp[48];
        int pos = 0;
        
        if (uval == 0) {
            temp[pos++] = '0';
        } else {
            while (uval > 0) {
                temp[pos++] = '0' + (uval % 10);
                uval /= 10;
            }
        }
        
        // Add sign if negative
        int buf_pos = 0;
        if (is_negative) {
            buffer[buf_pos++] = '-';
        }
        
        // Reverse the digits
        for (int i = pos - 1; i >= 0; i--) {
            buffer[buf_pos++] = temp[i];
        }
        buffer[buf_pos] = '\0';
        
        return buffer;
    #else
        // Fallback: treat as int64 if compiler doesn't support __int128
        int64_t val = *(int64_t*)value;
        return dsl_i64_to_string(val);
    #endif
}

char* dsl_u128_to_string(void* value) {
    // Full u128 support using unsigned __int128
    #if defined(__SIZEOF_INT128__)
        unsigned __int128 val = *(unsigned __int128*)value;
        char* buffer = (char*)malloc(48);  // Enough for 128-bit number + null
        if (!buffer) return NULL;
        
        // Convert to string (reverse order)
        char temp[48];
        int pos = 0;
        
        if (val == 0) {
            temp[pos++] = '0';
        } else {
            while (val > 0) {
                temp[pos++] = '0' + (val % 10);
                val /= 10;
            }
        }
        
        // Reverse the digits
        int buf_pos = 0;
        for (int i = pos - 1; i >= 0; i--) {
            buffer[buf_pos++] = temp[i];
        }
        buffer[buf_pos] = '\0';
        
        return buffer;
    #else
        // Fallback: treat as uint64 if compiler doesn't support __int128
        uint64_t val = *(uint64_t*)value;
        return dsl_u64_to_string(val);
    #endif
}

/* Legacy functions that remain */

char* dsl_int64_to_string(int64_t value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        snprintf(buffer, 32, "%ld", value);
    }
    return buffer;
}

/* ============================================================================
 * I/O Operations
 * ============================================================================ */

void dcl_print(const char* str) {
    if (str) {
        printf("%s", str);
    }
}

void dcl_println(const char* str) {
    if (str) {
        printf("%s\n", str);
    } else {
        printf("\n");
    }
}

char* dcl_input(const char* prompt) {
    if (prompt) {
        printf("%s", prompt);
    }
    
    char* buffer = (char*)malloc(1024);
    if (buffer && fgets(buffer, 1024, stdin)) {
        size_t len = strlen(buffer);
        if (len > 0 && buffer[len-1] == '\n') {
            buffer[len-1] = '\0';
        }
        return buffer;
    }
    
    return NULL;
}

/* ============================================================================
 * File Operations
 * ============================================================================ */

void* dsl_file_open(const char* path, const char* mode) {
    return (void*)fopen(path, mode);
}

void dsl_file_close(void* file) {
    if (file) {
        fclose((FILE*)file);
    }
}

int64_t dsl_file_read(void* file, void* buffer, int64_t size) {
    if (!file || !buffer) return -1;
    return (int64_t)fread(buffer, 1, (size_t)size, (FILE*)file);
}

int64_t dsl_file_write(void* file, const void* buffer, int64_t size) {
    if (!file || !buffer) return -1;
    return (int64_t)fwrite(buffer, 1, (size_t)size, (FILE*)file);
}

int64_t dsl_file_size(void* file) {
    if (!file) return -1;
    
    FILE* f = (FILE*)file;
    long current = ftell(f);
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, current, SEEK_SET);
    
    return (int64_t)size;
}

/* ============================================================================
 * Linux-specific System Calls
 * ============================================================================ */

void dsl_linux_sleep(uint32_t seconds) {
    sleep(seconds);
}

void dsl_linux_usleep(uint32_t microseconds) {
    usleep(microseconds);
}

uint32_t dsl_linux_getpid() {
    return (uint32_t)getpid();
}

void dsl_linux_exit(int32_t code) {
    exit(code);
}

// Console clear using ANSI escape codes
void dsl_linux_console_clear() {
    printf("\033[2J\033[H");
    fflush(stdout);
}

/* ============================================================================
 * Time Operations
 * ============================================================================ */

// Get current time in seconds since epoch (with microsecond precision)
double dsl_time_now() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec + (double)tv.tv_usec / 1000000.0;
}

// Get current time in milliseconds since epoch
int64_t dsl_time_now_ms() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (int64_t)tv.tv_sec * 1000 + (int64_t)tv.tv_usec / 1000;
}

// Get current time in nanoseconds (high resolution for benchmarking)
int64_t dsl_time_now_ns() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
}

// Sleep for specified seconds (can be fractional)
void dsl_time_sleep(double seconds) {
    if (seconds <= 0) return;
    usleep((useconds_t)(seconds * 1000000));
}

// Sleep for specified milliseconds
void dsl_time_sleep_ms(int64_t ms) {
    if (ms <= 0) return;
    usleep((useconds_t)(ms * 1000));
}
