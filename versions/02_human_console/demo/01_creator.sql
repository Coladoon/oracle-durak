SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- Пример:
-- @demo/01_creator.sql DURAK_OWNER Михаил demo-2026-08-29

DEFINE DURAK_OWNER = '&1'
DEFINE DISPLAY_NAME = '&2'
DEFINE GAME_SEED = '&3'

ALTER SESSION SET CURRENT_SCHEMA = &&DURAK_OWNER;

VARIABLE player_id NUMBER
VARIABLE game_id NUMBER
VARIABLE message VARCHAR2(1000)

BEGIN
    durak_api.register_player(
        p_player_id => :player_id,
        p_message => :message,
        p_display_name => '&&DISPLAY_NAME'
    );
END;
/

BEGIN
    durak_api.create_game(
        p_game_id => :game_id,
        p_message => :message,
        p_deck_size => 36,
        p_game_variant => 'PODKIDNOY',
        p_first_move_mode => 'LOWEST_TRUMP',
        p_seed_text => '&&GAME_SEED'
    );
END;
/

PRINT player_id
PRINT game_id
PRINT message

PROMPT Передайте значение GAME_ID второму игроку.

UNDEFINE DURAK_OWNER
UNDEFINE DISPLAY_NAME
UNDEFINE GAME_SEED
