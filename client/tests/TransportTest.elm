module TransportTest exposing (..)

import Test exposing (..)
import Test.Html.Query as Query
import Test.Html.Selector exposing (tag)
import Transport


suite : Test
suite =
    {- When I visit transport.beta.gouv.fr
       I want to know what they do,
       so that I can be reassured I'm in the right place,
       and build my shiny app around open transport data.
    -}
    describe "Landing"
        [ test "Shows startup's name" <|
            \() ->
                Transport.view
                    |> Query.fromHtml
                    |> Query.has [ tag "h1" ]
        , test "Shows unique value proposition" <|
            \_ ->
                Transport.view
                    |> Query.fromHtml
                    |> Query.has [ tag "h3" ]
        ]
