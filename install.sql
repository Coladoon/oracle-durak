SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

PROMPT ==============================================
PROMPT Установка проекта «Дурак»
PROMPT ==============================================

PROMPT [1/9] Создание схемы
@@sql/01_schema.sql

PROMPT [2/9] Заполнение справочника карт
@@sql/02_cards_seed.sql

PROMPT [3/9] Создание пакета детерминированного seed
@@sql/03_random_pkg.sql

PROMPT [4/9] Создание пакета правил
@@sql/04_rules_pkg.sql

PROMPT [5/9] Создание игрового автомата
@@sql/06_engine_pkg.sql

PROMPT [6/9] Создание публичного API
@@sql/07_api_pkg.sql

PROMPT [7/9] Создание обработчика таймеров
@@sql/08_maintenance_pkg.sql

PROMPT [8/9] Создание пользовательских представлений
@@sql/05_views.sql
@@sql/05_console_views.sql

PROMPT [8a/9] Создание человеко-понятной игровой консоли
@@sql/07_console_pkg.sql

DECLARE
    v_error_count PLS_INTEGER;
    v_invalid_count PLS_INTEGER;
BEGIN
    FOR r IN (
        SELECT name, type, line, position, text
        FROM user_errors
        WHERE name IN (
            'DURAK_RANDOM', 'DURAK_RULES', 'DURAK_ENGINE',
            'DURAK_API', 'DURAK_CONSOLE',
            'DURAK_MAINTENANCE',
            'V_CURRENT_PLAYER', 'V_GAME_STATUS', 'V_TABLE',
            'V_HAND_MINE', 'V_HAND_PUBLIC', 'V_LOG',
            'V_LEADERBOARD', 'V_DAILY', 'V_DAILY_RESULTS',
            'V_ERRORS', 'V_REPLAY',
            'V_GAME_CONSOLE', 'V_LOG_TEXT'
        )
        ORDER BY name, type, sequence
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            r.name || ' ' || r.type ||
            ' [' || r.line || ':' || r.position || '] ' || r.text
        );
    END LOOP;

    SELECT COUNT(*)
    INTO v_error_count
    FROM user_errors
    WHERE name IN (
        'DURAK_RANDOM', 'DURAK_RULES', 'DURAK_ENGINE',
        'DURAK_API', 'DURAK_CONSOLE',
        'DURAK_MAINTENANCE',
        'V_CURRENT_PLAYER', 'V_GAME_STATUS', 'V_TABLE',
        'V_HAND_MINE', 'V_HAND_PUBLIC', 'V_LOG',
        'V_LEADERBOARD', 'V_DAILY', 'V_DAILY_RESULTS',
        'V_ERRORS', 'V_REPLAY',
        'V_GAME_CONSOLE', 'V_LOG_TEXT'
    );

    SELECT COUNT(*)
    INTO v_invalid_count
    FROM user_objects
    WHERE object_name IN (
        'DURAK_RANDOM', 'DURAK_RULES', 'DURAK_ENGINE',
        'DURAK_API', 'DURAK_CONSOLE',
        'DURAK_MAINTENANCE',
        'V_CURRENT_PLAYER', 'V_GAME_STATUS', 'V_TABLE',
        'V_HAND_MINE', 'V_HAND_PUBLIC', 'V_LOG',
        'V_LEADERBOARD', 'V_DAILY', 'V_DAILY_RESULTS',
        'V_ERRORS', 'V_REPLAY',
        'V_GAME_CONSOLE', 'V_LOG_TEXT'
    )
      AND status <> 'VALID';

    IF v_error_count > 0 OR v_invalid_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20999, 'Обнаружены ошибки компиляции объектов DURAK.');
    END IF;
END;
/

PROMPT [9/9] Создание фонового задания таймеров
@@sql/09_scheduler.sql

COMMIT;
PROMPT ==============================================
PROMPT Проект «Дурак» установлен успешно.
PROMPT Для проверки выполните: @tests/run_all.sql
PROMPT ==============================================
