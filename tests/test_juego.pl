/*  Tests de src/juego.pl: cartas, sobre y reparto.  */

:- use_module(library(plunit)).
:- use_module('../src/juego').

% Todas las cartas que hay en una partida: las del sobre y las de las manos.
cartas_en_partida(partida(sobre(S, A, L), Manos, _, _, _), Ordenadas) :-
    findall(C, (member(_-Mano, Manos), member(C, Mano)), EnManos),
    msort([S, A, L|EnManos], Ordenadas).

mazo_ordenado(Mazo) :-
    findall(C, carta(_, C), Cartas),
    msort(Cartas, Mazo).

:- begin_tests(mazo).

test(hay_21_cartas) :-
    aggregate_all(count, carta(_, _), 21).

test(cartas_por_tipo) :-
    aggregate_all(count, carta(sospechoso, _), 6),
    aggregate_all(count, carta(arma, _), 6),
    aggregate_all(count, carta(lugar, _), 9).

test(sin_cartas_repetidas) :-
    findall(C, carta(_, C), Cartas),
    sort(Cartas, SinRepetir),
    length(Cartas, N),
    length(SinRepetir, N).

test(todas_tienen_nombre) :-
    forall(carta(_, C), nombre(C, _)).

test(nombre_sin_repetir) :-
    findall(N, nombre(_, N), Nombres),
    sort(Nombres, SinRepetir),
    length(Nombres, L),
    length(SinRepetir, L).

test(nombre_con_tilde, [true(Texto == 'Señora Coral')]) :-
    nombre(senora_coral, Texto).

test(tipo_de_una_carta, [true(Tipo == lugar)]) :-
    carta(Tipo, piscina).

:- end_tests(mazo).

:- begin_tests(partida).

test(estado_inicial, [forall(member(N, [3, 4, 5]))]) :-
    nueva_partida(N, partida(_, _, Turno, Eliminados, Historial)),
    Turno == 1,
    Eliminados == [],
    Historial == [].

test(el_sobre_tiene_una_carta_de_cada_tipo) :-
    forall(between(1, 30, _),
           ( nueva_partida(4, partida(sobre(S, A, L), _, _, _, _)),
             carta(sospechoso, S),
             carta(arma, A),
             carta(lugar, L) )).

test(las_21_cartas_aparecen_una_vez, [forall(member(N, [3, 4, 5]))]) :-
    forall(between(1, 100, _),
           ( nueva_partida(N, Partida),
             cartas_en_partida(Partida, Ordenadas),
             mazo_ordenado(Mazo),
             Ordenadas == Mazo )).

test(un_jugador_por_mano, [forall(member(N, [3, 4, 5]))]) :-
    nueva_partida(N, partida(_, Manos, _, _, _)),
    pairs_keys(Manos, Jugadores),
    numlist(1, N, Esperados),
    Jugadores == Esperados.

test(reparto_parejo, [forall(member(N, [3, 4, 5]))]) :-
    forall(between(1, 50, _),
           ( nueva_partida(N, partida(_, Manos, _, _, _)),
             pairs_values(Manos, Listas),
             maplist(length, Listas, Cuentas),
             sum_list(Cuentas, 18),
             max_list(Cuentas, Max),
             min_list(Cuentas, Min),
             Max - Min =< 1 )).

test(reparto_concreto_con_4_jugadores) :-
    nueva_partida(4, partida(_, Manos, _, _, _)),
    pairs_values(Manos, Listas),
    maplist(length, Listas, Cuentas),
    Cuentas == [5, 5, 4, 4].

test(misma_semilla_misma_partida) :-
    set_random(seed(7)), nueva_partida(4, P1),
    set_random(seed(7)), nueva_partida(4, P2),
    P1 == P2.

test(semillas_distintas_partidas_distintas) :-
    set_random(seed(1)), nueva_partida(4, P1),
    set_random(seed(2)), nueva_partida(4, P2),
    P1 \== P2.

test(demasiados_jugadores, [error(type_error(between(3, 5), 7))]) :-
    nueva_partida(7, _).

test(muy_pocos_jugadores, [error(type_error(between(3, 5), 2))]) :-
    nueva_partida(2, _).

:- end_tests(partida).
