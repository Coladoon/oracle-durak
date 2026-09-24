SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

ACCEPT GAME_ID NUMBER PROMPT 'Введите GAME_ID: '
ACCEPT PLAYER_ID NUMBER PROMPT 'Введите PLAYER_ID: '

DECLARE
BEGIN
    durak_engine.heartbeat(&PLAYER_ID, &GAME_ID);
    RAISE_APPLICATION_ERROR(
        -20896,
        'Операция неожиданно выполнилась при занятой партии.'
    );
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -20702 THEN
            DBMS_OUTPUT.PUT_LINE(
                '[OK] Конфликт корректно отклонён кодом -20702.'
            );
        ELSE
            RAISE;
        END IF;
END;
/

UNDEFINE GAME_ID
UNDEFINE PLAYER_ID
