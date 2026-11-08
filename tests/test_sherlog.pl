/*  Tests de src/sherlog.pl y src/jugar.pl: una partida completa por la terminal.  */

:- use_module(library(plunit)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module('../src/sherlog').

% Entrada: las primeras líneas dadas y, después, muchas líneas "1".
con_unos(Principio, Texto) :-
    length(Unos, 600),
    maplist(=("1\n"), Unos),
    atomics_to_string([Principio|Unos], Texto).

jugar_con_entrada(Texto, Rivales, Salida) :-
    open_string(Texto, Entrada),
    current_input(Anterior),
    setup_call_cleanup(
        set_input(Entrada),
        with_output_to(string(Salida), jugar_en_consola(Rivales)),
        ( set_input(Anterior), close(Entrada) )).

aparece(Texto, Trozo) :- sub_string(Texto, _, _, _, Trozo), !.

:- begin_tests(rivales).

test(los_niveles_son_azar_facil_media_y_dificil, [true(N == [azar, facil, media, dificil])]) :- niveles(N).
test(por_defecto_una_media_y_dos_faciles, [true(R == [media, facil, facil])]) :- rivales_por_defecto(R).

test(de_2_a_4_rivales_valen, [forall(member(R, [[facil, facil], [media, azar, facil], [media, media, media, media]]))]) :-
    rivales_validos(R).

test(uno_solo_no_vale, [fail]) :- rivales_validos([facil]).
test(cinco_no_valen, [fail]) :- rivales_validos([facil, facil, facil, facil, facil]).
test(ninguno_no_vale, [fail]) :- rivales_validos([]).
test(un_nivel_que_no_existe_no_vale, [fail]) :- rivales_validos([facil, robot]).
test(el_humano_no_es_un_rival, [fail]) :- rivales_validos([facil, humano]).

:- end_tests(rivales).

:- begin_tests(partida_por_la_terminal).

test(una_partida_completa_acaba_con_un_ganador, [forall(member(Rivales, [[facil, facil], [media, facil, azar], [azar, azar, media, facil], [dificil, azar]]))]) :-
    set_random(seed(3)),
    con_unos("", Entrada),
    jugar_con_entrada(Entrada, Rivales, Salida),
    aparece(Salida, "== Sherlog =="),
    aparece(Salida, "== Fin de la partida =="),
    aparece(Salida, "Gana "),
    aparece(Salida, "El sobre era:").

test(presenta_a_los_rivales) :-
    set_random(seed(3)),
    con_unos("", Entrada),
    jugar_con_entrada(Entrada, [media, azar], Salida),
    aparece(Salida, "jugador 2: IA media"),
    aparece(Salida, "jugador 3: IA azar").

test(el_humano_ve_las_jugadas_de_los_demas) :-
    set_random(seed(3)),
    con_unos("", Entrada),
    jugar_con_entrada(Entrada, [facil, facil], Salida),
    aparece(Salida, "El jugador 2 sugiere"),
    aparece(Salida, "El jugador 3 sugiere").

test(el_humano_que_acusa_mal_pierde_y_la_partida_termina) :-
    % Acusa en su primer turno con las primeras cartas de cada menú: casi
    % seguro que falla. Entonces queda eliminado y la partida termina ahí.
    set_random(seed(5)),
    con_unos("2\n1\n1\n1\n1\n", Entrada),
    jugar_con_entrada(Entrada, [facil, facil], Salida),
    aparece(Salida, "Te has equivocado y quedas eliminado"),
    aparece(Salida, "== Fin de la partida =="),
    aparece(Salida, "Has perdido"),
    aparece(Salida, "El sobre era:"),
    \+ aparece(Salida, "Gana ").

test(tras_perder_no_se_juega_ningun_turno_mas) :-
    % Después del aviso de que se ha equivocado no hay ni sugerencias de las
    % IAs ni otro turno: la partida no sigue solo entre IAs.
    set_random(seed(5)),
    con_unos("2\n1\n1\n1\n1\n", Entrada),
    jugar_con_entrada(Entrada, [facil, facil], Salida),
    once(sub_string(Salida, Pos, _, _, "Te has equivocado")),
    sub_string(Salida, Pos, _, 0, Resto),
    \+ aparece(Resto, "sugiere"),
    \+ aparece(Resto, "== Tu turno =="),
    aparece(Resto, "== Fin de la partida ==").

test(si_pierde_el_humano_la_partida_no_pide_mas_entrada) :-
    % Con la entrada justa para acusar (y nada más) la partida acaba bien: no
    % se queda esperando ni abandona por falta de entrada.
    set_random(seed(5)),
    jugar_con_entrada("2\n1\n1\n1\n1\n", [facil, facil], Salida),
    aparece(Salida, "Has perdido"),
    \+ aparece(Salida, "Partida abandonada").

test(si_se_acaba_la_entrada_la_partida_se_abandona) :-
    jugar_con_entrada("", [facil, facil], Salida),
    aparece(Salida, "Partida abandonada").

test(si_se_acaba_a_mitad_de_la_partida_tambien) :-
    set_random(seed(3)),
    jugar_con_entrada("1\n1\n1\n1\n", [facil, facil], Salida),
    aparece(Salida, "Partida abandonada"),
    \+ aparece(Salida, "== Fin de la partida ==").

:- end_tests(partida_por_la_terminal).

% El programa de verdad, como lo ejecutaría el usuario: otro proceso swipl.

programa(Argumentos, Entrada, Salida, Codigo) :-
    current_prolog_flag(executable, Swipl),
    module_property(sherlog, file(Fichero)),
    file_directory_name(Fichero, Src),
    atomic_list_concat([Src, '/jugar.pl'], Programa),
    process_create(Swipl, [Programa|Argumentos],
                   [stdin(pipe(In)), stdout(pipe(Out)), stderr(pipe(Err)), process(Pid)]),
    write(In, Entrada), close(In),
    read_string(Out, _, Salida), close(Out),
    read_string(Err, _, _), close(Err),
    process_wait(Pid, exit(Codigo)).

:- begin_tests(el_programa).

test(juega_una_partida_entera) :-
    con_unos("", Entrada),
    programa([facil, facil], Entrada, Salida, Codigo),
    Codigo == 0,
    aparece(Salida, "== Fin de la partida ==").

test(sin_argumentos_juega_contra_media_y_dos_faciles) :-
    con_unos("", Entrada),
    programa([], Entrada, Salida, Codigo),
    Codigo == 0,
    aparece(Salida, "jugador 2: IA media"),
    aparece(Salida, "jugador 3: IA facil"),
    aparece(Salida, "jugador 4: IA facil").

test(un_nivel_que_no_existe_da_error, [true(Codigo == 1)]) :-
    programa([robot, facil], "", _, Codigo).

test(con_un_solo_rival_da_error, [true(Codigo == 1)]) :-
    programa([facil], "", _, Codigo).

test(ctrl_d_abandona_sin_error, [true(Codigo == 0)]) :-
    programa([facil, facil], "", Salida, Codigo),
    aparece(Salida, "Partida abandonada").

:- end_tests(el_programa).
