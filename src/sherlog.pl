/*  Sherlog: una partida contra las IAs, jugada desde la terminal.

    Este módulo tiene la lógica; src/jugar.pl es solo el programa que lo
    arranca. Están separados porque cargar un programa con
    initialization(main, main) lo ejecuta, y los tests necesitan cargar
    esto sin que empiece una partida.

        juego.pl  <-  consola.pl  <-  jugador.pl  <-  turnos.pl  <-  sherlog.pl
*/

:- module(sherlog,
          [ jugar_en_consola/1,
            niveles/1,
            rivales_por_defecto/1,
            rivales_validos/1
          ]).

:- use_module(turnos).
:- use_module(consola).

%!  niveles(-Niveles) is det.
%
%   Los tipos de IA que se pueden elegir como rivales.

niveles([azar, facil, media, dificil]).

%!  rivales_por_defecto(-Rivales) is det.

rivales_por_defecto([media, facil, facil]).

%!  rivales_validos(+Rivales) is semidet.
%
%   De 2 a 4 rivales, cada uno de un nivel que existe.

rivales_validos(Rivales) :-
    niveles(Niveles),
    length(Rivales, N),
    between(2, 4, N),
    forall(member(R, Rivales), memberchk(R, Niveles)).

%!  jugar_en_consola(+Rivales) is det.
%
%   Juega una partida con el humano como jugador 1 y las IAs de la lista
%   como jugadores 2, 3...: jugar_en_consola([media, facil]) es una
%   partida de 3. Si la entrada se acaba, la partida se abandona. Si el
%   humano se equivoca al acusar, queda eliminado y la partida termina.

jugar_en_consola(Rivales) :-
    catch(partida(Rivales),
          error(fin_de_la_entrada, _),
          format("~nPartida abandonada.~n")).

partida(Rivales) :-
    iniciar_partida([humano|Rivales], Partida, Jugadores),
    presentar(Rivales),
    jugar(Partida, Jugadores, [termina_si_cae(1)], Resultado),
    mostrar_fin(1, Resultado).

presentar(Rivales) :-
    format("== Sherlog ==~n"),
    format("Alguien ha cometido un crimen. En el sobre están el sospechoso, el arma y el lugar.~n"),
    format("Eres el jugador 1. Juegas contra:~n"),
    forall(nth1(I, Rivales, Nivel),
           ( Id is I + 1,
             format("  jugador ~w: IA ~w~n", [Id, Nivel]) )),
    format("Escribe el número de la opción que quieras. Ctrl-D abandona.~n").
