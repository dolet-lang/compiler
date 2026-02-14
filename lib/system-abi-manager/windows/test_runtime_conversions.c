/*
 * Unit tests for Dolet runtime type conversion functions
 * Tests boundary values, zero conversion, and negative values
 * 
 * Compilation:
 *   Windows: clang -o test_runtime_conversions.exe test_runtime_conversions.c runtime.c
 *   Linux:   gcc -o test_runtime_conversions test_runtime_conversions.c runtime.c
 *   macOS:   clang -o test_runtime_conversions test_runtime_conversions.c runtime.c
 * 
 * Run:
 *   Windows: .\test_runtime_conversions.exe
 *   Linux:   ./test_runtime_conversions
 *   macOS:   ./test_runtime_conversions
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>

/* Function declarations */
char* dsl_i8_to_string(int8_t value);
char* dsl_i16_to_string(int16_t value);
char* dsl_i32_to_string(int32_t value);
char* dsl_i64_to_string(int64_t value);
char* dsl_u8_to_string(uint8_t value);
char* dsl_u16_to_string(uint16_t value);
char* dsl_u32_to_string(uint32_t value);
char* dsl_u64_to_string(uint64_t value);
char* dsl_f32_to_string(float value);
char* dsl_f64_to_string(double value);

/* Test counters */
static int tests_passed = 0;
static int tests_failed = 0;

/* Test helper */
void test_assert(const char* test_name, int condition) {
    if (condition) {
        printf("[PASS] %s\n", test_name);
        tests_passed++;
    } else {
        printf("[FAIL] %s\n", test_name);
        tests_failed++;
    }
}

/* Test i8 conversions */
void test_i8_conversions() {
    char* result;
    
    /* Test minimum value */
    result = dsl_i8_to_string(INT8_MIN);
    test_assert("i8 min value (-128)", strcmp(result, "-128") == 0);
    free(result);
    
    /* Test maximum value */
    result = dsl_i8_to_string(INT8_MAX);
    test_assert("i8 max value (127)", strcmp(result, "127") == 0);
    free(result);
    
    /* Test zero */
    result = dsl_i8_to_string(0);
    test_assert("i8 zero", strcmp(result, "0") == 0);
    free(result);
    
    /* Test negative value */
    result = dsl_i8_to_string(-42);
    test_assert("i8 negative value (-42)", strcmp(result, "-42") == 0);
    free(result);
}

/* Test i16 conversions */
void test_i16_conversions() {
    char* result;
    
    /* Test minimum value */
    result = dsl_i16_to_string(INT16_MIN);
    test_assert("i16 min value (-32768)", strcmp(result, "-32768") == 0);
    free(result);
    
    /* Test maximum value */
    result = dsl_i16_to_string(INT16_MAX);
    test_assert("i16 max value (32767)", strcmp(result, "32767") == 0);
    free(result);
    
    /* Test zero */
    result = dsl_i16_to_string(0);
    test_assert("i16 zero", strcmp(result, "0") == 0);
    free(result);
    
    /* Test negative value */
    result = dsl_i16_to_string(-1000);
    test_assert("i16 negative value (-1000)", strcmp(result, "-1000") == 0);
    free(result);
}

/* Test i32 conversions */
void test_i32_conversions() {
    char* result;
    
    /* Test minimum value */
    result = dsl_i32_to_string(INT32_MIN);
    test_assert("i32 min value (-2147483648)", strcmp(result, "-2147483648") == 0);
    free(result);
    
    /* Test maximum value */
    result = dsl_i32_to_string(INT32_MAX);
    test_assert("i32 max value (2147483647)", strcmp(result, "2147483647") == 0);
    free(result);
    
    /* Test zero */
    result = dsl_i32_to_string(0);
    test_assert("i32 zero", strcmp(result, "0") == 0);
    free(result);
    
    /* Test negative value */
    result = dsl_i32_to_string(-123456);
    test_assert("i32 negative value (-123456)", strcmp(result, "-123456") == 0);
    free(result);
}

/* Test i64 conversions */
void test_i64_conversions() {
    char* result;
    
    /* Test minimum value */
    result = dsl_i64_to_string(INT64_MIN);
    test_assert("i64 min value", strcmp(result, "-9223372036854775808") == 0);
    free(result);
    
    /* Test maximum value */
    result = dsl_i64_to_string(INT64_MAX);
    test_assert("i64 max value", strcmp(result, "9223372036854775807") == 0);
    free(result);
    
    /* Test zero */
    result = dsl_i64_to_string(0);
    test_assert("i64 zero", strcmp(result, "0") == 0);
    free(result);
    
    /* Test negative value */
    result = dsl_i64_to_string(-9876543210LL);
    test_assert("i64 negative value", strcmp(result, "-9876543210") == 0);
    free(result);
}

/* Test u8 conversions */
void test_u8_conversions() {
    char* result;
    
    /* Test minimum value */
    result = dsl_u8_to_string(0);
    test_assert("u8 min value (0)", strcmp(result, "0") == 0);
    free(result);
    
    /* Test maximum value */
    result = dsl_u8_to_string(UINT8_MAX);
    test_assert("u8 max value (255)", strcmp(result, "255") == 0);
    free(result);
    
    /* Test mid value */
    result = dsl_u8_to_string(128);
    test_assert("u8 mid value (128)", strcmp(result, "128") == 0);
    free(result);
}

/* Test u16 conversions */
void test_u16_conversions() {
    char* result;
    
    /* Test minimum value */
    result = dsl_u16_to_string(0);
    test_assert("u16 min value (0)", strcmp(result, "0") == 0);
    free(result);
    
    /* Test maximum value */
    result = dsl_u16_to_string(UINT16_MAX);
    test_assert("u16 max value (65535)", strcmp(result, "65535") == 0);
    free(result);
    
    /* Test mid value */
    result = dsl_u16_to_string(32768);
    test_assert("u16 mid value (32768)", strcmp(result, "32768") == 0);
    free(result);
}

/* Test u32 conversions */
void test_u32_conversions() {
    char* result;
    
    /* Test minimum value */
    result = dsl_u32_to_string(0);
    test_assert("u32 min value (0)", strcmp(result, "0") == 0);
    free(result);
    
    /* Test maximum value */
    result = dsl_u32_to_string(UINT32_MAX);
    test_assert("u32 max value (4294967295)", strcmp(result, "4294967295") == 0);
    free(result);
    
    /* Test mid value */
    result = dsl_u32_to_string(2147483648U);
    test_assert("u32 mid value (2147483648)", strcmp(result, "2147483648") == 0);
    free(result);
}

/* Test u64 conversions */
void test_u64_conversions() {
    char* result;
    
    /* Test minimum value */
    result = dsl_u64_to_string(0);
    test_assert("u64 min value (0)", strcmp(result, "0") == 0);
    free(result);
    
    /* Test maximum value */
    result = dsl_u64_to_string(UINT64_MAX);
    test_assert("u64 max value", strcmp(result, "18446744073709551615") == 0);
    free(result);
    
    /* Test mid value */
    result = dsl_u64_to_string(9223372036854775808ULL);
    test_assert("u64 mid value", strcmp(result, "9223372036854775808") == 0);
    free(result);
}

/* Test f32 conversions */
void test_f32_conversions() {
    char* result;
    
    /* Test zero */
    result = dsl_f32_to_string(0.0f);
    test_assert("f32 zero", strncmp(result, "0.0", 3) == 0);
    free(result);
    
    /* Test positive value */
    result = dsl_f32_to_string(3.14159f);
    test_assert("f32 positive value (3.14159)", strncmp(result, "3.14", 4) == 0);
    free(result);
    
    /* Test negative value */
    result = dsl_f32_to_string(-2.71828f);
    test_assert("f32 negative value (-2.71828)", result[0] == '-' && strncmp(result + 1, "2.71", 4) == 0);
    free(result);
}

/* Test f64 conversions */
void test_f64_conversions() {
    char* result;
    
    /* Test zero */
    result = dsl_f64_to_string(0.0);
    test_assert("f64 zero", strncmp(result, "0.0", 3) == 0);
    free(result);
    
    /* Test positive value */
    result = dsl_f64_to_string(3.141592653589793);
    test_assert("f64 positive value (pi)", strncmp(result, "3.14", 4) == 0);
    free(result);
    
    /* Test negative value */
    result = dsl_f64_to_string(-2.718281828459045);
    test_assert("f64 negative value (e)", result[0] == '-' && strncmp(result + 1, "2.71", 4) == 0);
    free(result);
}

int main() {
    printf("Running runtime conversion function tests...\n\n");
    
    test_i8_conversions();
    test_i16_conversions();
    test_i32_conversions();
    test_i64_conversions();
    test_u8_conversions();
    test_u16_conversions();
    test_u32_conversions();
    test_u64_conversions();
    test_f32_conversions();
    test_f64_conversions();
    
    printf("\n========================================\n");
    printf("Test Results:\n");
    printf("  Passed: %d\n", tests_passed);
    printf("  Failed: %d\n", tests_failed);
    printf("========================================\n");
    
    return tests_failed > 0 ? 1 : 0;
}
