/*
 * Dolet Runtime Library for Windows
 * Uses standard C library functions (portable across platforms)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#include <sys/time.h>
#endif

/* ============================================================================
 * Path Resolution (for relative file paths)
 * ============================================================================ */

/**
 * Resolve a relative path against a base directory.
 * If path is absolute (starts with / or C:\ etc), returns path unchanged.
 * Otherwise, combines base_dir and path.
 * Returns newly allocated string that caller must free.
 */
char* dsl_resolve_path(const char* base_dir, const char* path) {
    if (!path || !path[0]) {
        return NULL;
    }
    
    // Check if path is already absolute
    // Windows: C:\ D:\ etc or starts with backslash
    // Unix: starts with /
    int is_absolute = 0;
    if (path[0] == '/' || path[0] == '\\') {
        is_absolute = 1;
    }
    #ifdef _WIN32
    // Check for drive letter (C:, D:, etc)
    if (path[0] && path[1] == ':') {
        is_absolute = 1;
    }
    #endif
    
    if (is_absolute || !base_dir || !base_dir[0]) {
        // Return copy of original path
        size_t len = strlen(path);
        char* result = (char*)malloc(len + 1);
        if (result) {
            strcpy(result, path);
        }
        return result;
    }
    
    // Combine base_dir and path
    size_t base_len = strlen(base_dir);
    size_t path_len = strlen(path);
    
    // Check if base_dir ends with separator
    int needs_sep = 1;
    if (base_len > 0 && (base_dir[base_len-1] == '/' || base_dir[base_len-1] == '\\')) {
        needs_sep = 0;
    }
    
    size_t total_len = base_len + path_len + (needs_sep ? 1 : 0) + 1;
    char* result = (char*)malloc(total_len);
    if (result) {
        strcpy(result, base_dir);
        if (needs_sep) {
            #ifdef _WIN32
            strcat(result, "\\");
            #else
            strcat(result, "/");
            #endif
        }
        strcat(result, path);
    }
    return result;
}

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

/* String extension methods for extend str */

char* dsl_str_to_upper(const char* str) {
    if (!str) return NULL;
    size_t len = strlen(str);
    char* result = (char*)malloc(len + 1);
    if (!result) return NULL;
    for (size_t i = 0; i <= len; i++) {
        char c = str[i];
        if (c >= 'a' && c <= 'z') {
            result[i] = c - 32;
        } else {
            result[i] = c;
        }
    }
    return result;
}

char* dsl_str_to_lower(const char* str) {
    if (!str) return NULL;
    size_t len = strlen(str);
    char* result = (char*)malloc(len + 1);
    if (!result) return NULL;
    for (size_t i = 0; i <= len; i++) {
        char c = str[i];
        if (c >= 'A' && c <= 'Z') {
            result[i] = c + 32;
        } else {
            result[i] = c;
        }
    }
    return result;
}

int32_t dsl_str_contains(const char* str, const char* substr) {
    if (!str || !substr) return 0;
    return strstr(str, substr) != NULL ? 1 : 0;
}

int32_t dsl_str_starts_with(const char* str, const char* prefix) {
    if (!str || !prefix) return 0;
    size_t prefix_len = strlen(prefix);
    size_t str_len = strlen(str);
    if (prefix_len > str_len) return 0;
    return strncmp(str, prefix, prefix_len) == 0 ? 1 : 0;
}

int32_t dsl_str_ends_with(const char* str, const char* suffix) {
    if (!str || !suffix) return 0;
    size_t suffix_len = strlen(suffix);
    size_t str_len = strlen(str);
    if (suffix_len > str_len) return 0;
    return strcmp(str + str_len - suffix_len, suffix) == 0 ? 1 : 0;
}

char* dsl_str_trim(const char* str) {
    if (!str) return NULL;
    
    // Skip leading whitespace
    const char* start = str;
    while (*start && (*start == ' ' || *start == '\t' || *start == '\n' || *start == '\r')) {
        start++;
    }
    
    // Find end (skip trailing whitespace)
    const char* end = str + strlen(str) - 1;
    while (end >= start && (*end == ' ' || *end == '\t' || *end == '\n' || *end == '\r')) {
        end--;
    }
    
    size_t len = end - start + 1;
    char* result = (char*)malloc(len + 1);
    if (!result) return NULL;
    strncpy(result, start, len);
    result[len] = '\0';
    return result;
}

char* dsl_str_substring(const char* str, int64_t start_idx, int64_t end_idx) {
    if (!str) return NULL;
    
    size_t str_len = strlen(str);
    
    // Clamp indices to valid range
    if (start_idx < 0) start_idx = 0;
    if (end_idx > (int64_t)str_len) end_idx = str_len;
    if (start_idx >= end_idx) {
        // Return empty string
        char* result = (char*)malloc(1);
        if (result) result[0] = '\0';
        return result;
    }
    
    size_t len = end_idx - start_idx;
    char* result = (char*)malloc(len + 1);
    if (!result) return NULL;
    strncpy(result, str + start_idx, len);
    result[len] = '\0';
    return result;
}

/* ============================================================================
 * Type Conversions (for printing)
 * ============================================================================ */

/* New explicit type conversion functions */

char* dsl_i8_to_string(int8_t value) {
    char* buffer = (char*)malloc(8);  // -128 to 127 (max 4 chars + sign + null)
    if (buffer) {
        sprintf(buffer, "%d", (int)value);
    }
    return buffer;
}

char* dsl_i16_to_string(int16_t value) {
    char* buffer = (char*)malloc(16);  // -32768 to 32767 (max 6 chars + sign + null)
    if (buffer) {
        sprintf(buffer, "%d", (int)value);
    }
    return buffer;
}

char* dsl_i32_to_string(int32_t value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        sprintf(buffer, "%d", value);
    }
    return buffer;
}

char* dsl_i64_to_string(int64_t value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        sprintf(buffer, "%lld", value);
    }
    return buffer;
}

char* dsl_u8_to_string(uint8_t value) {
    char* buffer = (char*)malloc(8);  // 0 to 255 (max 3 chars + null)
    if (buffer) {
        sprintf(buffer, "%u", (unsigned int)value);
    }
    return buffer;
}

char* dsl_u16_to_string(uint16_t value) {
    char* buffer = (char*)malloc(16);  // 0 to 65535 (max 5 chars + null)
    if (buffer) {
        sprintf(buffer, "%u", (unsigned int)value);
    }
    return buffer;
}

char* dsl_u32_to_string(uint32_t value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        sprintf(buffer, "%u", value);
    }
    return buffer;
}

char* dsl_u64_to_string(uint64_t value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        sprintf(buffer, "%llu", value);
    }
    return buffer;
}

char* dsl_f32_to_string(float value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        sprintf(buffer, "%f", value);
    }
    return buffer;
}

char* dsl_f64_to_string(double value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        sprintf(buffer, "%lf", value);
    }
    return buffer;
}

/* ============================================================================
 * Type Conversion Helpers (for Dolet runtime.dlt)
 * These allow pure Dolet code to perform type conversions
 * ============================================================================ */

// Convert f64 to i32 (truncates decimal part)
int32_t dsl_f64_to_i32(double value) {
    return (int32_t)value;
}

// Convert i64 to i32 (truncates to 32 bits)
int32_t dsl_i64_to_i32(int64_t value) {
    return (int32_t)value;
}

// Convert f64 to i64 (truncates decimal part)
int64_t dsl_f64_to_i64(double value) {
    return (int64_t)value;
}

// Convert i32 to f64
double dsl_i32_to_f64(int32_t value) {
    return (double)value;
}

// Convert i64 to f64
double dsl_i64_to_f64(int64_t value) {
    return (double)value;
}

/* Legacy functions that remain */

char* dsl_int64_to_string(int64_t value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        sprintf(buffer, "%lld", value);
    }
    return buffer;
}

char* dsl_bool_to_string(int32_t value) {
    if (value) {
        char* result = (char*)malloc(5);
        if (result) strcpy(result, "true");
        return result;
    } else {
        char* result = (char*)malloc(6);
        if (result) strcpy(result, "false");
        return result;
    }
}

char* dsl_char_to_string(char value) {
    char* buffer = (char*)malloc(2);
    if (buffer) {
        buffer[0] = value;
        buffer[1] = '\0';
    }
    return buffer;
}

char* dsl_uint64_to_string(uint64_t value) {
    char* buffer = (char*)malloc(32);
    if (buffer) {
        sprintf(buffer, "%llu", value);
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

/* ============================================================================
 * String Operations
 * ============================================================================ */

char* dsl_string_concat(const char* str1, const char* str2) {
    if (!str1) str1 = "";
    if (!str2) str2 = "";
    
    size_t len1 = strlen(str1);
    size_t len2 = strlen(str2);
    char* result = (char*)malloc(len1 + len2 + 1);
    
    if (result) {
        strcpy(result, str1);
        strcat(result, str2);
    }
    
    return result;
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

void dsl_println(const char* str) {
    dcl_println(str);
}

void dsl_flush() {
    fflush(stdout);
}

char* dcl_input(const char* prompt) {
    if (prompt) {
        printf("%s", prompt);
    }
    
    char* buffer = (char*)malloc(1024);
    if (buffer && fgets(buffer, 1024, stdin)) {
        // Remove trailing newline
        size_t len = strlen(buffer);
        if (len > 0 && buffer[len-1] == '\n') {
            buffer[len-1] = '\0';
        }
        return buffer;
    }
    
    return NULL;
}

/* ============================================================================
 * File Operations (Windows-specific)
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
 * Platform Utilities (using standard C)
 * ============================================================================ */

// Exit program
void dsl_exit(int32_t code) {
    exit(code);
}

// Clear console (portable way)
void dsl_console_clear() {
    #ifdef _WIN32
        system("cls");
    #else
        system("clear");
    #endif
}

/* ============================================================================
 * List Operations
 * ============================================================================ */

// List structure: { size: i32, capacity: i32, data: ptr }
typedef struct {
    int32_t size;
    int32_t capacity;
    void* data;
} List;

int32_t dsl_list_get_i32(void* list_ptr, int32_t index) {
    if (!list_ptr) return 0;
    List* list = (List*)list_ptr;
    if (index < 0 || index >= list->size) return 0;
    int32_t* data = (int32_t*)list->data;
    return data[index];
}

int64_t dsl_list_get_i64(void* list_ptr, int32_t index) {
    if (!list_ptr) return 0;
    List* list = (List*)list_ptr;
    if (index < 0 || index >= list->size) return 0;
    int64_t* data = (int64_t*)list->data;
    return data[index];
}

void* dsl_list_get_string(void* list_ptr, int32_t index) {
    if (!list_ptr) return NULL;
    List* list = (List*)list_ptr;
    if (index < 0 || index >= list->size) return NULL;
    void** data = (void**)list->data;
    return data[index];
}

/* ============================================================================
 * HashMap Operations (Robin Hood hashing)
 * ============================================================================ */

// Hash functions
uint64_t dsl_hash_i32(int32_t key) {
    // FNV-1a hash
    uint64_t hash = 14695981039346656037ULL;
    uint8_t* bytes = (uint8_t*)&key;
    for (size_t i = 0; i < sizeof(int32_t); i++) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }
    return hash;
}

uint64_t dsl_hash_i64(int64_t key) {
    // FNV-1a hash
    uint64_t hash = 14695981039346656037ULL;
    uint8_t* bytes = (uint8_t*)&key;
    for (size_t i = 0; i < sizeof(int64_t); i++) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }
    return hash;
}

uint64_t dsl_hash_string(const char* key) {
    if (!key) return 0;
    // FNV-1a hash
    uint64_t hash = 14695981039346656037ULL;
    while (*key) {
        hash ^= (uint8_t)(*key++);
        hash *= 1099511628211ULL;
    }
    return hash;
}

// HashMap entry
typedef struct {
    uint64_t hash;
    void* key;
    void* value;
    int32_t occupied;
    int32_t distance;  // For Robin Hood hashing
} HashMapEntry;

// HashMap structure
typedef struct {
    int32_t size;
    int32_t capacity;
    HashMapEntry* entries;
} HashMap;

void* dsl_hashmap_create(int32_t capacity) {
    HashMap* map = (HashMap*)malloc(sizeof(HashMap));
    if (!map) return NULL;
    
    map->size = 0;
    map->capacity = capacity > 0 ? capacity : 16;
    map->entries = (HashMapEntry*)calloc(map->capacity, sizeof(HashMapEntry));
    
    if (!map->entries) {
        free(map);
        return NULL;
    }
    
    return map;
}

void dsl_hashmap_destroy(void* map_ptr) {
    if (!map_ptr) return;
    HashMap* map = (HashMap*)map_ptr;
    if (map->entries) free(map->entries);
    free(map);
}

int32_t dsl_hashmap_insert(void* map_ptr, uint64_t hash, void* key, void* value) {
    if (!map_ptr) return 0;
    HashMap* map = (HashMap*)map_ptr;
    
    // Find insertion point using Robin Hood hashing
    int32_t index = (int32_t)(hash % map->capacity);
    int32_t distance = 0;
    
    HashMapEntry entry = {hash, key, value, 1, 0};
    
    while (1) {
        if (!map->entries[index].occupied) {
            // Empty slot found
            entry.distance = distance;
            map->entries[index] = entry;
            map->size++;
            return 1;
        }
        
        // Robin Hood: steal from rich
        if (map->entries[index].distance < distance) {
            HashMapEntry temp = map->entries[index];
            entry.distance = distance;
            map->entries[index] = entry;
            entry = temp;
            distance = entry.distance;
        }
        
        index = (index + 1) % map->capacity;
        distance++;
        
        // Prevent infinite loop
        if (distance > map->capacity) break;
    }
    
    return 0;
}

void* dsl_hashmap_get(void* map_ptr, uint64_t hash, void* key, void* comparator) {
    if (!map_ptr) return NULL;
    HashMap* map = (HashMap*)map_ptr;
    
    int32_t index = (int32_t)(hash % map->capacity);
    int32_t distance = 0;
    
    while (distance < map->capacity) {
        if (!map->entries[index].occupied) {
            return NULL;  // Not found
        }
        
        if (map->entries[index].hash == hash) {
            // Found potential match - caller must verify key
            return map->entries[index].value;
        }
        
        // Robin Hood: if we passed where it should be, it doesn't exist
        if (map->entries[index].distance < distance) {
            return NULL;
        }
        
        index = (index + 1) % map->capacity;
        distance++;
    }
    
    return NULL;
}

int32_t dsl_hashmap_get_entries(void* map_ptr, void* keys_out, void* values_out) {
    if (!map_ptr) return 0;
    HashMap* map = (HashMap*)map_ptr;
    
    int32_t count = 0;
    void** keys = (void**)keys_out;
    void** values = (void**)values_out;
    
    for (int32_t i = 0; i < map->capacity; i++) {
        if (map->entries[i].occupied) {
            if (keys) keys[count] = map->entries[i].key;
            if (values) values[count] = map->entries[i].value;
            count++;
        }
    }
    
    return count;
}

// Key comparison functions
int32_t dsl_key_equals_i32(void* key1, void* key2) {
    if (!key1 || !key2) return 0;
    return *(int32_t*)key1 == *(int32_t*)key2;
}

int32_t dsl_key_equals_i64(void* key1, void* key2) {
    if (!key1 || !key2) return 0;
    return *(int64_t*)key1 == *(int64_t*)key2;
}

int32_t dsl_key_equals_string(void* key1, void* key2) {
    if (!key1 || !key2) return 0;
    return strcmp((const char*)key1, (const char*)key2) == 0;
}

/* ============================================================================
 * Memory Write Helpers for Struct Initialization
 * These functions safely write values to memory addresses
 * ============================================================================ */

// Write i32 value to memory address
void dsl_write_i32(void* addr, int32_t value) {
    if (addr) {
        *(int32_t*)addr = value;
    }
}

// Write i64 value to memory address
void dsl_write_i64(void* addr, int64_t value) {
    if (addr) {
        *(int64_t*)addr = value;
    }
}

// Write f32 value to memory address
void dsl_write_f32(void* addr, float value) {
    if (addr) {
        *(float*)addr = value;
    }
}

// Write f64 value to memory address
void dsl_write_f64(void* addr, double value) {
    if (addr) {
        *(double*)addr = value;
    }
}

// Write pointer (i64) value to memory address
void dsl_write_ptr(void* addr, void* value) {
    if (addr) {
        *(void**)addr = value;
    }
}

// Write i8 byte to memory address
void dsl_write_i8(void* addr, int8_t value) {
    if (addr) {
        *(int8_t*)addr = value;
    }
}

// Write i16 value to memory address
void dsl_write_i16(void* addr, int16_t value) {
    if (addr) {
        *(int16_t*)addr = value;
    }
}

// Read i32 value from memory address
int32_t dsl_read_i32(void* addr) {
    if (addr) {
        return *(int32_t*)addr;
    }
    return 0;
}

// Read i64 value from memory address
int64_t dsl_read_i64(void* addr) {
    if (addr) {
        return *(int64_t*)addr;
    }
    return 0;
}

// Read f32 value from memory address
float dsl_read_f32(void* addr) {
    if (addr) {
        return *(float*)addr;
    }
    return 0.0f;
}

// Read f64 value from memory address
double dsl_read_f64(void* addr) {
    if (addr) {
        return *(double*)addr;
    }
    return 0.0;
}

// Read pointer from memory address
void* dsl_read_ptr(void* addr) {
    if (addr) {
        return *(void**)addr;
    }
    return NULL;
}

/* ============================================================================
 * Time Operations
 * ============================================================================ */

// Get current time in seconds since epoch (with microsecond precision)
double dsl_time_now() {
    #ifdef _WIN32
        FILETIME ft;
        GetSystemTimeAsFileTime(&ft);
        // FILETIME is 100-nanosecond intervals since January 1, 1601
        // Convert to seconds since Unix epoch (January 1, 1970)
        uint64_t time = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
        // Subtract difference between 1601 and 1970 (in 100-ns intervals)
        time -= 116444736000000000ULL;
        // Convert to seconds with fractional part
        return (double)time / 10000000.0;
    #else
        struct timeval tv;
        gettimeofday(&tv, NULL);
        return (double)tv.tv_sec + (double)tv.tv_usec / 1000000.0;
    #endif
}

// Get current time in milliseconds since epoch
int64_t dsl_time_now_ms() {
    #ifdef _WIN32
        FILETIME ft;
        GetSystemTimeAsFileTime(&ft);
        uint64_t time = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
        time -= 116444736000000000ULL;
        return (int64_t)(time / 10000);  // Convert to milliseconds
    #else
        struct timeval tv;
        gettimeofday(&tv, NULL);
        return (int64_t)tv.tv_sec * 1000 + (int64_t)tv.tv_usec / 1000;
    #endif
}

// Get current time in nanoseconds (high resolution for benchmarking)
int64_t dsl_time_now_ns() {
    #ifdef _WIN32
        LARGE_INTEGER freq, counter;
        QueryPerformanceFrequency(&freq);
        QueryPerformanceCounter(&counter);
        // Convert to nanoseconds
        return (int64_t)((double)counter.QuadPart / (double)freq.QuadPart * 1000000000.0);
    #else
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
    #endif
}

// Sleep for specified seconds (can be fractional)
void dsl_time_sleep(double seconds) {
    if (seconds <= 0) return;
    #ifdef _WIN32
        Sleep((DWORD)(seconds * 1000));
    #else
        usleep((useconds_t)(seconds * 1000000));
    #endif
}

// Sleep for specified milliseconds
void dsl_time_sleep_ms(int64_t ms) {
    if (ms <= 0) return;
    #ifdef _WIN32
        Sleep((DWORD)ms);
    #else
        usleep((useconds_t)(ms * 1000));
    #endif
}
