SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- Пример просмотра:
-- @demo/07_human_console.sql DURAK_OWNER 2102

DEFINE DURAK_OWNER = '&1'
DEFINE GAME_ID = '&2'

ALTER SESSION SET CURRENT_SCHEMA = &&DURAK_OWNER;

VARIABLE message VARCHAR2(1000)

SELECT game_text, turn_text, hand_text, table_text,
       players_text, command_hint, last_event_text
FROM v_game_console
WHERE game_id = &&GAME_ID;

PROMPT Для хода выполните одну строку, например:
PROMPT EXEC DURAK_CONSOLE.PLAY('ХОД 8H', :message)
PROMPT EXEC DURAK_CONSOLE.PLAY('БИТО 9H 1', :message)
PROMPT EXEC DURAK_CONSOLE.PLAY('ПОДКИНУТЬ 8C', :message)
PROMPT EXEC DURAK_CONSOLE.PLAY('ПЕРЕВОД 8D', :message)
PROMPT EXEC DURAK_CONSOLE.PLAY('ВЗЯТЬ', :message)
PROMPT EXEC DURAK_CONSOLE.PLAY('ПАС', :message)
PROMPT PRINT message

UNDEFINE DURAK_OWNER
UNDEFINE GAME_ID
