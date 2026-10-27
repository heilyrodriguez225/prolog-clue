/*  Sherlog: cartas, jugadores y reparto.

    Las reglas y las cartas están descritas en PLAN.md §2.
*/

:- module(juego,
          [ carta/2,
            nombre/2,
            nueva_partida/2
          ]).

:- use_module(library(random)).
:- use_module(library(lists)).

%!  carta(?Tipo, ?Carta) is nondet.
%
%   Las 21 cartas del mazo. Tipo es sospechoso, arma o lugar.

carta(sospechoso, chef_canela).
carta(sospechoso, entrenador_cobalto).
carta(sospechoso, senora_coral).
carta(sospechoso, jardinero_verde).
carta(sospechoso, doctora_violeta).
carta(sospechoso, senorita_perla).

carta(arma, trofeo).
carta(arma, veneno).
carta(arma, cuerda).
carta(arma, daga).
carta(arma, revolver).
carta(arma, tijeras).

carta(lugar, biblioteca).
carta(lugar, cocina).
carta(lugar, sala_de_video).
carta(lugar, piscina).
carta(lugar, comedor).
carta(lugar, estudio).
carta(lugar, bodega).
carta(lugar, gimnasio).
carta(lugar, jardin).

%!  nombre(?Carta, ?Texto) is nondet.
%
%   Nombre de cada carta para mostrar al jugador.

nombre(chef_canela,        'Chef Canela').
nombre(entrenador_cobalto, 'Entrenador Cobalto').
nombre(senora_coral,       'Señora Coral').
nombre(jardinero_verde,    'Jardinero Verde').
nombre(doctora_violeta,    'Doctora Violeta').
nombre(senorita_perla,     'Señorita Perla').

nombre(trofeo,   'Trofeo').
nombre(veneno,   'Veneno').
nombre(cuerda,   'Cuerda').
nombre(daga,     'Daga').
nombre(revolver, 'Revólver').
nombre(tijeras,  'Tijeras').

nombre(biblioteca,    'Biblioteca').
nombre(cocina,        'Cocina').
nombre(sala_de_video, 'Sala de video').
nombre(piscina,       'Piscina').
nombre(comedor,       'Comedor').
nombre(estudio,       'Estudio').
nombre(bodega,        'Bodega').
nombre(gimnasio,      'Gimnasio').
nombre(jardin,        'Jardín').

%!  elegir_sobre(-Sobre) is det.
%
%   Sobre es sobre(Sospechoso, Arma, Lugar), con una carta al azar de
%   cada tipo: la solución de la partida.

elegir_sobre(sobre(S, A, L)) :-
    al_azar(sospechoso, S),
    al_azar(arma, A),
    al_azar(lugar, L).

% Una carta al azar del tipo dado.
al_azar(Tipo, Carta) :-
    findall(C, carta(Tipo, C), Cartas),
    random_member(Carta, Cartas).

%!  repartir(+NJugadores, +Sobre, -Manos) is det.
%
%   Baraja las cartas que no están en el sobre y las reparte en ronda.
%   Manos es una lista Jugador-Cartas: [1-[...], 2-[...], ...].

repartir(N, sobre(S, A, L), Manos) :-
    findall(C, carta(_, C), Todas),
    subtract(Todas, [S, A, L], Resto),
    random_permutation(Resto, Baraja),
    findall(J-Mano,
            ( between(1, N, J),
              findall(C, (nth1(I, Baraja, C), I mod N =:= J mod N), Mano) ),
            Manos).

%!  nueva_partida(+NJugadores, -Partida) is det.
%
%   Crea una partida de 3 a 5 jugadores (el 1 es el humano):
%
%       partida(Sobre, Manos, Turno, Eliminados, Historial)
%
%   Empieza el jugador 1, sin eliminados y con el historial vacío.
%   Ver PLAN.md §2, "El estado de la partida".

nueva_partida(N, partida(Sobre, Manos, 1, [], [])) :-
    must_be(between(3, 5), N),
    elegir_sobre(Sobre),
    repartir(N, Sobre, Manos).
