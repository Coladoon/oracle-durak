SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- Пример:
-- @demo/05_daily_bot.sql DURAK_OWNER Михаил HARD

DEFINE DURAK_OWNER = '&1'
DEFINE DISPLAY_NAME = '&2'
DEFINE BOT_LEVEL = '&3'

ALTER SESSION SET CURRENT_SCHEMA = &&DURAK_OWNER;

VARIABLE player_id NUMBER
VARIABLE game_id NUMBER
VARIABLE daily_id NUMBER
VARIABLE bot_player_id NUMBER
VARIABLE bot_seat_no NUMBER
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
    durak_api.create_daily_game(
        p_game_id => :game_id,
        p_daily_id => :daily_id,
        p_message => :message,
        p_deck_size => 36,
        p_game_variant => 'PODKIDNOY',
        p_first_move_mode => 'LOWEST_TRUMP'
    );
END;
/

BEGIN
    durak_api.add_bot(
        p_game_id => :game_id,
        p_bot_player_id => :bot_player_id,
        p_seat_no => :bot_seat_no,
        p_message => :message,
        p_bot_level => '&&BOT_LEVEL'
    );
END;
/

BEGIN
    durak_api.start_game(
        p_game_id => :game_id,
        p_message => :message
    );
END;
/

PRINT game_id
PRINT daily_id
PRINT bot_player_id
PRINT bot_seat_no
PRINT message

SELECT phase, current_actor_name, my_allowed_actions,
       trump_card_code, talon_count
FROM v_game_status
WHERE game_id = :game_id
  AND seat_no = viewer_seat_no;

SELECT event_no, event_type, event_source, actor_name, card_code, event_message
FROM v_log
WHERE game_id = :game_id
ORDER BY event_no;

PROMPT Боты продолжают игру автоматически после каждого действия человека.
PROMPT После завершения смотрите V_REPLAY, V_ANALYTICS и V_DAILY_RESULTS.

UNDEFINE DURAK_OWNER
UNDEFINE DISPLAY_NAME
UNDEFINE BOT_LEVEL
