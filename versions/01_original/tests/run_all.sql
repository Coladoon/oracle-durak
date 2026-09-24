SET DEFINE OFF
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

PROMPT Установка тестового пакета
@@00_test_support.sql

DECLARE
    v_invalid NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO v_invalid
    FROM user_errors
    WHERE name = 'DURAK_TEST';

    IF v_invalid > 0 THEN
        RAISE_APPLICATION_ERROR(-20898, 'Пакет DURAK_TEST скомпилирован с ошибками.');
    END IF;
END;
/

BEGIN
    durak_test.reset;
END;
/

@@01_cards_test.sql
@@02_rules_test.sql
@@03_random_test.sql
@@04_views_test.sql
@@05_objects_test.sql
@@06_engine_test.sql
@@07_extensions_test.sql
@@08_tournament_test.sql

BEGIN
    durak_test.finish;
END;
/

PROMPT Все тесты DURAK завершены успешно
