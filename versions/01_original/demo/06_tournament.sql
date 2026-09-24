SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- Пример:
-- @demo/06_tournament.sql DURAK_OWNER Михаил ROUND_ROBIN

DEFINE DURAK_OWNER = '&1'
DEFINE DISPLAY_NAME = '&2'
DEFINE TOURNAMENT_FORMAT = '&3'

ALTER SESSION SET CURRENT_SCHEMA = &&DURAK_OWNER;

VARIABLE player_id NUMBER
VARIABLE tournament_id NUMBER
VARIABLE bot1_id NUMBER
VARIABLE bot2_id NUMBER
VARIABLE message VARCHAR2(1000)

BEGIN
    durak_api.register_player(
        p_player_id => :player_id,
        p_message => :message,
        p_display_name => '&&DISPLAY_NAME'
    );

    durak_api.create_tournament(
        p_tournament_id => :tournament_id,
        p_message => :message,
        p_tournament_name => 'Демонстрационный турнир',
        p_tournament_format => '&&TOURNAMENT_FORMAT',
        p_seed_text => 'demo-tournament-seed'
    );

    durak_api.add_tournament_bot(
        p_tournament_id => :tournament_id,
        p_bot_player_id => :bot1_id,
        p_message => :message,
        p_bot_level => 'EASY'
    );

    durak_api.add_tournament_bot(
        p_tournament_id => :tournament_id,
        p_bot_player_id => :bot2_id,
        p_message => :message,
        p_bot_level => 'HARD'
    );

    durak_api.start_tournament(
        p_tournament_id => :tournament_id,
        p_message => :message
    );
END;
/

PRINT tournament_id
PRINT bot1_id
PRINT bot2_id
PRINT message

SELECT tournament_round_no, match_no, tournament_match_id,
       player1_name, player2_name, match_status
FROM v_tournament
WHERE tournament_id = :tournament_id
ORDER BY tournament_round_no, match_no;

SELECT standing_place, seed_no, display_name, player_status,
       points, wins_count, losses_count, draws_count
FROM v_tournament_standings
WHERE tournament_id = :tournament_id
ORDER BY standing_place, seed_no;

PROMPT Запустите выбранный матч через DURAK_API.START_TOURNAMENT_MATCH.

UNDEFINE DURAK_OWNER
UNDEFINE DISPLAY_NAME
UNDEFINE TOURNAMENT_FORMAT
