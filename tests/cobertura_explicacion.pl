/*  Sherlog: contrasta el metaintérprete (explicacion.pl) con el motor CLP(FD).

    Dos preguntas sobre lo que explica la IA:

        Corrección   ¿lo que el metaintérprete prueba es cierto? Se compara
                     con el motor (deduccion.pl) y con el sobre real.
                     Tiene que dar 0 contradicciones.

        Cobertura    de lo que el motor sabe con certeza (cartas descartadas
                     o en el sobre), ¿cuánto sabe explicar el metaintérprete?

    No forma parte de tests/todos.pl porque tarda unos minutos.

    Uso, desde la raíz del proyecto:

        swipl tests/cobertura_explicacion.pl            30 partidas, semilla 2026
        swipl tests/cobertura_explicacion.pl 10 7       10 partidas, semilla 7

    Cada partida mezcla IAs media y difícil (3 a 5 jugadores). Después de
    cada turno se mira a todas las IAs, no solo al final, porque lo difícil
    de explicar son los momentos intermedios. Termina con código 0 si no
    hay ninguna contradicción y con 1 si la hay.
*/

:- use_module(library(main)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).
:- use_module(library(random)).
:- use_module('../src/turnos').
:- use_module('../src/jugador').
:- use_module('../src/deduccion').
:- use_module('../src/explicacion').

:- initialization(main, main).

:- dynamic contador/2.

main(Argumentos) :-
    argumentos(Argumentos, N, Semilla),
    set_random(seed(Semilla)),
    format("Sherlog: cobertura de la explicación, ~w partidas (semilla ~w)~n~n", [N, Semilla]),
    statistics(cputime, T0),
    forall(between(1, N, I), una_partida(I)),
    statistics(cputime, T1),
    Total is T1 - T0,
    informe(Total, Bien),
    (   Bien == true -> halt(0) ; halt(1) ).

argumentos([], 30, 2026).
argumentos([N], N1, 2026) :- atom_number(N, N1).
argumentos([N, S|_], N1, S1) :- atom_number(N, N1), atom_number(S, S1).

suma(Clave, V) :-
    (   retract(contador(Clave, V0)) -> true ; V0 = 0 ),
    V1 is V0 + V,
    assertz(contador(Clave, V1)).

maximo(Clave, V) :-
    (   retract(contador(Clave, V0)) -> true ; V0 = 0 ),
    V1 is max(V0, V),
    assertz(contador(Clave, V1)).

% ---------------------------------------------------------------------------
% Una partida, turno a turno
% ---------------------------------------------------------------------------

una_partida(I) :-
    NJ is 3 + I mod 3,
    length(Tipos, NJ),
    maplist(un_tipo, Tipos),
    iniciar_partida(Tipos, Partida, Jugadores),
    Partida = partida(Sobre, _, _, _, _),
    turno(Partida, Jugadores, Sobre, 0),
    suma(partidas, 1).

un_tipo(T) :- random_member(T, [media, media, dificil]).

turno(Partida, Jugadores, Sobre, Pasos) :-
    Pasos < 200,
    jugadores_en_juego(Partida, [_, _|_]),
    Partida = partida(_, _, Quien, _, _),
    accion_del_turno(Partida, Jugadores, Accion, Jugadores1),
    (   Accion = sugerir(S, A, L)
    ->  jugar_sugerencia(Partida, Jugadores1, Quien, [S, A, L], Partida1, Jugadores2),
        comprobar(Jugadores2, Sobre),
        siguiente_turno(Partida1, Partida2),
        Pasos1 is Pasos + 1,
        turno(Partida2, Jugadores2, Sobre, Pasos1)
    ;   Accion = acusar(S, A, L),
        comprobar_acusacion(Jugadores1, Quien, [S, A, L]),
        jugar_acusacion(Partida, Jugadores1, Quien, [S, A, L], Resultado, Partida1, Jugadores2),
        (   Resultado == acierta
        ->  true
        ;   siguiente_turno(Partida1, Partida2),
            Pasos1 is Pasos + 1,
            turno(Partida2, Jugadores2, Sobre, Pasos1)
        )
    ).
turno(_, _, _, _).

% ---------------------------------------------------------------------------
% Comprobaciones
% ---------------------------------------------------------------------------

comprobar(Jugadores, Sobre) :-
    forall(( member(jugador(Id, _, mente(K, _, R)), Jugadores) ),
           comprobar_ia(Id, K, R, Sobre)).

comprobar_ia(Id, K, R, Sobre) :-
    sobre_a_lista(Sobre, Reales),
    deducir(K, Estados),
    forall(member(C-E, Estados), comprobar_carta(Id, K, R, Reales, C, E)).

sobre_a_lista(sobre(S, A, L), [S, A, L]).

comprobar_carta(Id, _, R, Reales, C, Estado) :-
    estado_probado(R, C, Probado, Segundos),
    maximo(segundos_maximos, Segundos),
    suma(consultas, 1),
    suma(tiempo, Segundos),
    (   Estado == dudosa
    ->  (   Probado == ninguno
        ->  true
        ;   suma(contradicciones, 1),
            format("CONTRADICCIÓN: la IA ~w prueba ~w de ~w, el motor dice dudosa~n", [Id, Probado, C])
        )
    ;   Estado == descartada
    ->  suma(motor_descartada, 1),
        (   Probado == descartada -> suma(explica_descartada, 1)
        ;   Probado == ninguno -> true
        ;   suma(contradicciones, 1),
            format("CONTRADICCIÓN: la IA ~w prueba ~w de ~w, el motor dice descartada~n", [Id, Probado, C])
        )
    ;   Estado == sobre
    ->  suma(motor_sobre, 1),
        (   Probado == en_sobre -> suma(explica_sobre, 1)
        ;   Probado == ninguno -> true
        ;   suma(contradicciones, 1),
            format("CONTRADICCIÓN: la IA ~w prueba ~w de ~w, el motor dice sobre~n", [Id, Probado, C])
        )
    ),
    % Contra la verdad: lo probado tiene que cumplirse en la partida real.
    (   Probado == en_sobre, \+ memberchk(C, Reales)
    ->  suma(contradicciones, 1),
        format("CONTRADICCIÓN con el sobre real: ~w no está en el sobre~n", [C])
    ;   Probado == descartada, memberchk(C, Reales)
    ->  suma(contradicciones, 1),
        format("CONTRADICCIÓN con el sobre real: ~w sí está en el sobre~n", [C])
    ;   true
    ).

% Qué sabe probar el metaintérprete de la carta, y cuánto tarda.
estado_probado(R, C, Probado, Segundos) :-
    statistics(cputime, T0),
    (   prueba(R, en_sobre(C), _)   -> Probado = en_sobre
    ;   prueba(R, descartada(C), _) -> Probado = descartada
    ;   Probado = ninguno
    ),
    statistics(cputime, T1),
    Segundos is T1 - T0.

% Al acusar: ¿sabe explicar las tres cartas?
comprobar_acusacion(Jugadores, Quien, Cartas) :-
    member(jugador(Quien, _, mente(_, _, R)), Jugadores),
    !,
    suma(acusaciones, 1),
    (   forall(member(C, Cartas), prueba(R, en_sobre(C), _))
    ->  suma(acusaciones_explicadas, 1)
    ;   suma(acusaciones_sin_explicar, 1)
    ).
comprobar_acusacion(_, _, _).

% ---------------------------------------------------------------------------
% Informe
% ---------------------------------------------------------------------------

valor(Clave, V) :- ( contador(Clave, V0) -> V = V0 ; V = 0 ).

informe(Total, Bien) :-
    valor(partidas, P), valor(consultas, Q), valor(contradicciones, Contra),
    valor(motor_descartada, MD), valor(explica_descartada, ED),
    valor(motor_sobre, MS), valor(explica_sobre, ES),
    valor(acusaciones, Ac), valor(acusaciones_explicadas, AE),
    valor(segundos_maximos, Max), valor(tiempo, TQ),
    pct(ED, MD, PD), pct(ES, MS, PS), pct(AE, Ac, PA),
    (   Q > 0 -> Media is 1000 * TQ / Q ; Media = 0 ),
    format("~nPartidas: ~w · cartas miradas (IA, turno, carta): ~w · tiempo total ~1f s~n", [P, Q, Total]),
    format("Contradicciones con el motor o con el sobre real: ~w~n", [Contra]),
    format("Cartas descartadas que el motor sabe: ~w · explicadas: ~w (~1f %)~n", [MD, ED, PD]),
    format("Cartas en el sobre que el motor sabe: ~w · explicadas: ~w (~1f %)~n", [MS, ES, PS]),
    format("Acusaciones (de las IAs que acusaron): ~w · con las 3 cartas explicadas: ~w (~1f %)~n", [Ac, AE, PA]),
    format("Tiempo por carta: ~3f ms de media, ~3f s el máximo~n", [Media, Max]),
    (   Contra =:= 0 -> Bien = true ; Bien = false ).

pct(_, 0, 100.0) :- !.
pct(A, B, P) :- P is 100.0 * A / B.
