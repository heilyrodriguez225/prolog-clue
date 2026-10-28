/*  Demo: la IA (jugador 1) deduce la solución en una partida de
    21 cartas y 4 jugadores, a partir de lo que ve en cada turno.

    La partida está escrita a mano para que la demo dé siempre el mismo
    resultado y las observaciones sean coherentes con el reparto.

    Uso:  swipl src/demo.pl
*/

:- use_module(juego).
:- use_module(deduccion).

:- initialization(main, main).

partida_demo(partida(sobre(senora_coral, cuerda, gimnasio),
                     [ 1-[chef_canela, daga, biblioteca, cocina, piscina],
                       2-[entrenador_cobalto, trofeo, sala_de_video, comedor, jardin],
                       3-[doctora_violeta, veneno, estudio, bodega],
                       4-[jardinero_verde, senorita_perla, revolver, tijeras]
                     ],
                     1, [], [])).

% Lo que la IA 1 ve en cada turno: descripción y observación.
turno('Sugiero Entrenador Cobalto, Revólver, Gimnasio. El jugador 2 me enseña Entrenador Cobalto.',
      mostro(2, entrenador_cobalto)).
turno('El jugador 2 sugiere Señora Coral, Veneno, Jardín. El jugador 3 refuta (no veo la carta).',
      refuto(3, [senora_coral, veneno, jardin])).
turno('El jugador 3 sugiere Doctora Violeta, Tijeras, Comedor. El jugador 4 refuta.',
      refuto(4, [doctora_violeta, tijeras, comedor])).
turno('Sugiero Señora Coral, Cuerda, Sala de video. El jugador 2 me enseña Sala de video.',
      mostro(2, sala_de_video)).
turno('Sugiero Señora Coral, Cuerda, Biblioteca (la biblioteca es mía). Nadie puede refutar.',
      no_refuto([2, 3, 4], [senora_coral, cuerda, biblioteca])).
turno('El jugador 3 sugiere Doctora Violeta, Veneno, Gimnasio. Ni el 4 ni el 2 pueden refutar.',
      no_refuto([4, 2], [doctora_violeta, veneno, gimnasio])).
turno('Sugiero Chef Canela, Daga, Gimnasio (las dos primeras son mías). Nadie puede refutar.',
      no_refuto([2, 3, 4], [chef_canela, daga, gimnasio])).

% Aplicar una observación al conocimiento K.
observar(K, mostro(J, C))       :- mostro(K, J, C).
observar(K, refuto(J, Cs))      :- refuto(K, J, Cs).
observar(K, no_refuto(Js, Cs))  :- maplist(no_pudo(K, Cs), Js).

% Ojo: no usar una lambda [J]>>... aquí, porque copiaría K y las
% restricciones se añadirían a la copia, no al conocimiento real.
no_pudo(K, Cs, J) :- no_refuto(K, J, Cs).

main :-
    partida_demo(Partida),
    conocimiento_inicial(1, Partida, K),
    writeln('Soy la IA del jugador 1. Mis cartas: Chef Canela, Daga, Biblioteca, Cocina y Piscina.'),
    resumen(K),
    findall(T-O, turno(T, O), Turnos),
    foldl(jugar_turno(K), Turnos, 1, _),
    acusar(K).

jugar_turno(K, Texto-Obs, N, N1) :-
    format("~nTurno ~w: ~w~n", [N, Texto]),
    observar(K, Obs),
    resumen(K),
    N1 is N + 1.

resumen(K) :-
    deducir(K, Estados),
    findall(C, member(C-sobre, Estados), Sobre),
    aggregate_all(count, member(_-descartada, Estados), NDesc),
    aggregate_all(count, member(_-dudosa, Estados), NDud),
    maplist(nombre, Sobre, Nombres),
    format("  En el sobre: ~w · descartadas: ~w · dudosas: ~w~n", [Nombres, NDesc, NDud]).

acusar(K) :-
    (   solucion_segura(K, sobre(S0, A0, L0))
    ->  maplist(nombre, [S0, A0, L0], [S, A, L]),
        format("~nLa IA acusa: fue ~w, con ~w, en ~w.~n", [S, A, L])
    ;   writeln('\nTodavía no hay suficiente información para acusar.')
    ).
