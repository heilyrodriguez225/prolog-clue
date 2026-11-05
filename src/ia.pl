/*  Sherlog: el pensamiento de cada IA.

    Aquí vive lo que decide cada nivel de IA, sobre datos puros (listas
    de cartas, no jugadores). jugador.pl conecta estas decisiones con el
    protocolo de la partida.

    IA fácil: su memoria son las cartas que ha visto (las suyas y las que
    le han enseñado). Sabe que ninguna de ellas está en el sobre.

        juego.pl  <-  deduccion.pl  <-  ia.pl  <-  jugador.pl  <-  turnos.pl
*/

:- module(ia,
          [ cartas_sin_ver/3,
            facil_recordar/3,
            facil_sugerencia/2,
            facil_accion/2
          ]).

:- use_module(library(lists)).
:- use_module(library(random)).
:- use_module(library(error)).
:- use_module(juego, [carta/2]).

%!  cartas_sin_ver(+Tipo, +Vistas, -Cartas) is det.
%
%   Cartas son las cartas del Tipo (sospechoso, arma o lugar) que no
%   están en Vistas: las que aún podrían estar en el sobre.

cartas_sin_ver(Tipo, Vistas, Cartas) :-
    findall(C,
            ( carta(Tipo, C), \+ memberchk(C, Vistas) ),
            Cartas).

%!  facil_recordar(+Evento, +Vistas, -Vistas1) is det.
%
%   La IA fácil solo recuerda las cartas que le enseñan: un evento
%   carta_vista(_, Carta) añade la carta a las vistas, sin repetirla.
%   Cualquier otro evento lo ignora.

facil_recordar(Evento, Vistas, Vistas1) :-
    (   Evento = carta_vista(_, Carta),
        \+ memberchk(Carta, Vistas)
    ->  Vistas1 = [Carta|Vistas]
    ;   Vistas1 = Vistas
    ).

%!  facil_sugerencia(+Vistas, -Sugerencia) is det.
%
%   Sugerencia es sugerir(S, A, L), con un sospechoso, un arma y un lugar
%   elegidos al azar entre los que la IA fácil todavía no ha visto.
%   Sugerir cartas que ya ha visto sería malgastar el turno: sabe que
%   no están en el sobre.

facil_sugerencia(Vistas, sugerir(S, A, L)) :-
    una_sin_ver(sospechoso, Vistas, S),
    una_sin_ver(arma, Vistas, A),
    una_sin_ver(lugar, Vistas, L).

% Una carta al azar del tipo dado, entre las que no están en Vistas.
% Si no queda ninguna es que las Vistas son imposibles: el sobre tiene
% siempre una carta de cada tipo, que nadie ha podido enseñar.
una_sin_ver(Tipo, Vistas, Carta) :-
    cartas_sin_ver(Tipo, Vistas, Cartas),
    (   Cartas == []
    ->  existence_error(carta_sin_ver, Tipo)
    ;   random_member(Carta, Cartas)
    ).

%!  facil_accion(+Vistas, -Accion) is det.
%
%   Lo que hace la IA fácil en su turno.
%
%       - Si de cada tipo (sospechoso, arma y lugar) le queda UNA sola
%         carta sin ver, esas tres tienen que ser las del sobre: acusa.
%       - Si no, sugiere (facil_sugerencia/2).
%
%   Solo acusa cuando está segura, así que nunca falla. La contrapartida
%   es que necesita ver casi todas las demás cartas antes de acusar; la
%   IA media, que deduce de lo que ocurre en la mesa, llegará antes.

facil_accion(Vistas, Accion) :-
    cartas_sin_ver(sospechoso, Vistas, Sospechosos),
    cartas_sin_ver(arma, Vistas, Armas),
    cartas_sin_ver(lugar, Vistas, Lugares),
    (   Sospechosos = [S], Armas = [A], Lugares = [L]
    ->  Accion = acusar(S, A, L)
    ;   facil_sugerencia(Vistas, Accion)
    ).
