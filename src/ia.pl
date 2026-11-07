/*  Sherlog: el pensamiento de cada IA.

    Aquí vive lo que decide cada nivel de IA, sobre datos puros (listas
    de cartas, no jugadores). jugador.pl conecta estas decisiones con el
    protocolo de la partida.

    IA fácil: su memoria son las cartas que ha visto (las suyas y las que
    le han enseñado). Sabe que ninguna de ellas está en el sobre.

    IA media: su memoria es un conocimiento de deduccion.pl, con
    restricciones CLP(FD). Convierte en restricciones todo lo que ve en la
    mesa, también las sugerencias de los demás, y deduce qué cartas pueden
    estar en el sobre.

        juego.pl  <-  deduccion.pl  <-  ia.pl  <-  jugador.pl  <-  turnos.pl
*/

:- module(ia,
          [ cartas_sin_ver/3,
            facil_recordar/3,
            facil_sugerencia/2,
            facil_accion/2,
            media_observar/3,
            media_accion/2,
            media_carta_a_mostrar/5
          ]).

:- use_module(library(lists)).
:- use_module(library(random)).
:- use_module(library(error)).
:- use_module(juego, [carta/2]).
:- use_module(deduccion).

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

%   ---------------------------------------------------------------------
%   IA media

%!  media_observar(+Yo, +Evento, +K) is det.
%
%   La IA media (el jugador Yo, con conocimiento K) ve un Evento. Lo
%   convierte en restricciones y las añade a K, que es el mismo término
%   (las restricciones viven en sus variables).
%
%       sugerencia(Quien, Cartas, Respuestas)
%           no_pudo(J)    J no tiene ninguna de las tres cartas
%           refuto(J)     J tiene al menos una de las tres (no se sabe cuál)
%       carta_vista(J, Carta)
%           J tiene Carta
%       acusacion(_, Cartas, falla)
%           las tres cartas no son, juntas, las del sobre
%
%   Lo que le ocurre a la propia IA no aporta nada nuevo: no necesita
%   enterarse de que ella misma no pudo refutar, y si ella refutó, ya
%   sabe lo que enseñó. Y cuando es ella quien sugiere y alguien refuta,
%   la carta concreta le llega aparte como carta_vista/2, que dice más
%   que el simple "tiene alguna".
%
%   Las restricciones se añaden con maplist y predicados auxiliares,
%   nunca con forall ni con lambdas: forall las desharía al terminar y
%   las lambdas copiarían K, así que se perderían en los dos casos.

media_observar(Yo, Evento, K) :-
    (   Evento = sugerencia(Quien, Cartas, Respuestas)
    ->  maplist(media_respuesta(K, Yo, Quien, Cartas), Respuestas)
    ;   Evento = carta_vista(J, Carta)
    ->  mostro(K, J, Carta)
    ;   Evento = acusacion(_, Cartas, falla)
    ->  acusacion_fallida(K, Cartas)
    ;   true
    ).

media_respuesta(K, Yo, Quien, Cartas, Respuesta) :-
    (   Respuesta = no_pudo(J), J \== Yo
    ->  no_refuto(K, J, Cartas)
    ;   Respuesta = refuto(J), J \== Yo, Quien \== Yo
    ->  refuto(K, J, Cartas)
    ;   true
    ).

%!  media_accion(+K, -Accion) is det.
%
%   Lo que hace la IA media en su turno.
%
%       - Si de cada tipo solo queda UNA carta que pueda estar en el
%         sobre (es lo que comprueba solucion_segura/2), acusa.
%       - Si no, sugiere una carta de cada tipo entre las que todavía
%         pueden estar en el sobre.
%
%   A diferencia de la IA fácil, no necesita haber visto las cartas: le
%   basta con deducir que no pueden estar en el sobre. Y como solo
%   acusa cuando el motor de restricciones lo demuestra, nunca falla.

media_accion(K, Accion) :-
    posibles_de_tipo(K, sospechoso, Sospechosos),
    posibles_de_tipo(K, arma, Armas),
    posibles_de_tipo(K, lugar, Lugares),
    (   Sospechosos = [S], Armas = [A], Lugares = [L]
    ->  Accion = acusar(S, A, L)
    ;   una_de(sospechoso, Sospechosos, S),
        una_de(arma, Armas, A),
        una_de(lugar, Lugares, L),
        Accion = sugerir(S, A, L)
    ).

% Una carta al azar de la lista. Una lista vacía es imposible: el sobre
% tiene siempre una carta de cada tipo.
una_de(Tipo, Cartas, Carta) :-
    (   Cartas == []
    ->  existence_error(carta_posible, Tipo)
    ;   random_member(Carta, Cartas)
    ).

%!  media_carta_a_mostrar(+Mostradas, +Quien, +Candidatas, -Carta, -Mostradas1) is det.
%
%   La IA media tiene que refutar una sugerencia de Quien y tiene las
%   Candidatas. Elige cuál enseñar procurando dar la menor información
%   posible. Mostradas es lo que ya ha enseñado, una lista de Jugador-Carta.
%
%   Cada carta que enseña le dice a quien la ve que no está en el sobre y
%   que la tiene ella. Por eso:
%
%       1. Si ya le enseñó a Quien alguna de las Candidatas, repite esa:
%          no le cuenta nada nuevo.
%       2. Si no, prefiere una que ya haya enseñado a otro jugador: así se
%          descubren menos cartas distintas de su mano.
%       3. Si no hay ninguna, una al azar.
%
%   Mostradas1 recuerda lo que acaba de enseñar, sin repetir entradas.

media_carta_a_mostrar(Mostradas, Quien, Candidatas, Carta, Mostradas1) :-
    (   member(Repetida, Candidatas),
        memberchk(Quien-Repetida, Mostradas)
    ->  Carta = Repetida
    ;   findall(C, ( member(C, Candidatas), memberchk(_-C, Mostradas) ), YaEnseniadas),
        YaEnseniadas = [_|_]
    ->  random_member(Carta, YaEnseniadas)
    ;   random_member(Carta, Candidatas)
    ),
    (   memberchk(Quien-Carta, Mostradas)
    ->  Mostradas1 = Mostradas
    ;   Mostradas1 = [Quien-Carta|Mostradas]
    ).
