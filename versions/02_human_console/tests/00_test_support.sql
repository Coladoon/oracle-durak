PROMPT Создание минимального набора SQL-тестов DURAK_TEST

CREATE OR REPLACE PACKAGE durak_test AUTHID DEFINER AS
    PROCEDURE reset;

    PROCEDURE pass (
        p_name IN VARCHAR2
    );

    PROCEDURE fail (
        p_name    IN VARCHAR2,
        p_details IN VARCHAR2
    );

    PROCEDURE assert_number (
        p_name     IN VARCHAR2,
        p_expected IN NUMBER,
        p_actual   IN NUMBER
    );

    PROCEDURE assert_text (
        p_name     IN VARCHAR2,
        p_expected IN VARCHAR2,
        p_actual   IN VARCHAR2
    );

    PROCEDURE assert_raw_equal (
        p_name     IN VARCHAR2,
        p_expected IN RAW,
        p_actual   IN RAW
    );

    PROCEDURE assert_raw_not_equal (
        p_name  IN VARCHAR2,
        p_left  IN RAW,
        p_right IN RAW
    );

    PROCEDURE assert_between (
        p_name   IN VARCHAR2,
        p_actual IN NUMBER,
        p_low    IN NUMBER,
        p_high   IN NUMBER
    );

    PROCEDURE finish;
END durak_test;
/

CREATE OR REPLACE PACKAGE BODY durak_test AS
    g_passed PLS_INTEGER := 0;
    g_failed PLS_INTEGER := 0;

    PROCEDURE reset IS
    BEGIN
        g_passed := 0;
        g_failed := 0;
        DBMS_OUTPUT.PUT_LINE('--- Запуск тестов DURAK ---');
    END reset;

    PROCEDURE pass (
        p_name IN VARCHAR2
    ) IS
    BEGIN
        g_passed := g_passed + 1;
        DBMS_OUTPUT.PUT_LINE('[OK] ' || p_name);
    END pass;

    PROCEDURE fail (
        p_name    IN VARCHAR2,
        p_details IN VARCHAR2
    ) IS
    BEGIN
        g_failed := g_failed + 1;
        DBMS_OUTPUT.PUT_LINE('[FAIL] ' || p_name || ': ' || p_details);
    END fail;

    PROCEDURE assert_number (
        p_name     IN VARCHAR2,
        p_expected IN NUMBER,
        p_actual   IN NUMBER
    ) IS
    BEGIN
        IF (p_expected IS NULL AND p_actual IS NULL)
           OR p_expected = p_actual THEN
            pass(p_name);
        ELSE
            fail(
                p_name,
                'ожидалось ' || NVL(TO_CHAR(p_expected), 'NULL')
                || ', получено ' || NVL(TO_CHAR(p_actual), 'NULL')
            );
        END IF;
    END assert_number;

    PROCEDURE assert_text (
        p_name     IN VARCHAR2,
        p_expected IN VARCHAR2,
        p_actual   IN VARCHAR2
    ) IS
    BEGIN
        IF (p_expected IS NULL AND p_actual IS NULL)
           OR p_expected = p_actual THEN
            pass(p_name);
        ELSE
            fail(
                p_name,
                'ожидалось "' || NVL(p_expected, 'NULL')
                || '", получено "' || NVL(p_actual, 'NULL') || '"'
            );
        END IF;
    END assert_text;

    PROCEDURE assert_raw_equal (
        p_name     IN VARCHAR2,
        p_expected IN RAW,
        p_actual   IN RAW
    ) IS
    BEGIN
        IF (p_expected IS NULL AND p_actual IS NULL)
           OR (
               p_expected IS NOT NULL
               AND p_actual IS NOT NULL
               AND UTL_RAW.COMPARE(p_expected, p_actual) = 0
           ) THEN
            pass(p_name);
        ELSE
            fail(
                p_name,
                'RAW-значения различаются: '
                || NVL(RAWTOHEX(p_expected), 'NULL') || ' / '
                || NVL(RAWTOHEX(p_actual), 'NULL')
            );
        END IF;
    END assert_raw_equal;

    PROCEDURE assert_raw_not_equal (
        p_name  IN VARCHAR2,
        p_left  IN RAW,
        p_right IN RAW
    ) IS
    BEGIN
        IF p_left IS NOT NULL
           AND p_right IS NOT NULL
           AND UTL_RAW.COMPARE(p_left, p_right) <> 0 THEN
            pass(p_name);
        ELSE
            fail(p_name, 'ожидались два разных непустых RAW-значения');
        END IF;
    END assert_raw_not_equal;

    PROCEDURE assert_between (
        p_name   IN VARCHAR2,
        p_actual IN NUMBER,
        p_low    IN NUMBER,
        p_high   IN NUMBER
    ) IS
    BEGIN
        IF p_actual BETWEEN p_low AND p_high THEN
            pass(p_name);
        ELSE
            fail(
                p_name,
                NVL(TO_CHAR(p_actual), 'NULL') || ' не входит в диапазон '
                || TO_CHAR(p_low) || '..' || TO_CHAR(p_high)
            );
        END IF;
    END assert_between;

    PROCEDURE finish IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(
            '--- Итого: успешно ' || g_passed || ', ошибок ' || g_failed || ' ---'
        );

        IF g_failed > 0 THEN
            RAISE_APPLICATION_ERROR(
                -20899,
                'Тесты DURAK завершились с ошибками: ' || g_failed
            );
        END IF;
    END finish;
END durak_test;
/

SHOW ERRORS PACKAGE durak_test
SHOW ERRORS PACKAGE BODY durak_test
