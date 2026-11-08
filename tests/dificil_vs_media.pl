/*  Sherlog: la IA difícil contra la media.

    Mide si la ganancia de información sirve de algo. No forma parte de
    tests/todos.pl porque tarda varios minutos.

    Uso, desde la raíz del proyecto:

        swipl tests/dificil_vs_media.pl              50 partidas, semilla 2026
        swipl tests/dificil_vs_media.pl 20 7         20 partidas, semilla 7

    Cada partida es de tres jugadores: una difícil y dos medias, y la
    difícil cambia de asiento en cada partida (para que el orden de turno
    no ayude a nadie). Si todos jugaran igual, cada uno ganaría una de cada
    tres partidas (33 %).

    Termina con código 0 si ninguna partida da error, la difícil nunca
    queda eliminada (nunca acusa mal) y ninguna decisión tarda 2 s o más;
    con 1 si no. Si gana o no a la media se cuenta al final, pero no cambia
    el código: depende del azar.
*/

:- use_module(library(main)).
:- use_module(library(lists)).
:- use_module(library(aggregate)).
:- use_module('../src/ia', [dificil_accion/2]).
:- use_module('../src/turnos').

:- initialization(main, main).

main(Argumentos) :-
    argumentos(Argumentos, N, Semilla),
    set_random(seed(Semilla)),
    format("Sherlog: difícil contra media, ~w partidas de 3 jugadores (semilla ~w)~n~n", [N, Semilla]),
    statistics(cputime, T0),
    findall(R, ( between(1, N, I), jugar_una(I, R) ), Resultados),
    statistics(cputime, T1),
    Total is T1 - T0,
    informe(Resultados, N, Total, Bien),
    (   Bien == true -> halt(0) ; halt(1) ).

argumentos([], 50, 2026).
argumentos([N], N1, 2026) :- atom_number(N, N1).
argumentos([N, S|_], N1, S1) :- atom_number(N, N1), atom_number(S, S1).

% Una partida: la difícil se sienta en el asiento 1, 2 o 3 por turnos.
jugar_una(I, r(Asiento, Ganador, Motivo, Eliminada, Tiempo, Decision)) :-
    Asiento is (I - 1) mod 3 + 1,
    findall(T, ( between(1, 3, J), ( J =:= Asiento -> T = dificil ; T = media ) ), Tipos),
    iniciar_partida(Tipos, Partida, Jugadores),
    jugador_con_id(Asiento, Jugadores, jugador(_, dificil, mente(K, _))),
    statistics(cputime, T0),
    dificil_accion(K, _),                         % lo que tarda una decisión
    statistics(cputime, T1),
    Decision is T1 - T0,
    jugar(Partida, Jugadores, fin(Ganador, Motivo, partida(_, _, _, Eliminados, _), _)),
    statistics(cputime, T2),
    Tiempo is T2 - T1,
    (   memberchk(Asiento, Eliminados) -> Eliminada = true ; Eliminada = false ).

informe(Resultados, N, Total, Bien) :-
    aggregate_all(count, ( member(r(A, G, _, _, _, _), Resultados), A == G ), Gana),
    aggregate_all(count, member(r(_, _, _, true, _, _), Resultados), Eliminadas),
    aggregate_all(max(D), member(r(_, _, _, _, _, D), Resultados), PeorDecision),
    aggregate_all(count, ( member(r(_, _, _, _, _, D2), Resultados), D2 >= 2.0 ), Lentas),
    length(Resultados, Jugadas),
    Pct is 100.0 * Gana / N,
    format("Gana la difícil: ~w de ~w (~1f %; si todos jugaran igual, 33 %)~n", [Gana, N, Pct]),
    forall(between(1, 3, A),
           ( aggregate_all(count, member(r(A, _, _, _, _, _), Resultados), En),
             aggregate_all(count, ( member(r(A, G, _, _, _, _), Resultados), G == A ), Ga),
             format("  sentada en el asiento ~w: ~w de ~w~n", [A, Ga, En]) )),
    format("Decisión más lenta: ~3f s (límite 2 s); decisiones de 2 s o más: ~w~n", [PeorDecision, Lentas]),
    format("La difícil eliminada por acusar mal: ~w~n", [Eliminadas]),
    format("Tiempo total: ~1f s~n~n", [Total]),
    (   Gana * 2 > N
    ->  format("Gana a la media en la mayoría de las partidas.~n")
    ;   format("NO gana a la media en la mayoría de las partidas.~n")
    ),
    (   Jugadas =:= N, Eliminadas =:= 0, Lentas =:= 0
    ->  Bien = true
    ;   Bien = false
    ).
