module Transport exposing (..)

import Html exposing (..)


-- MAIN


main : Html String
main =
    view



-- VIEW


view : Html String
view =
    div []
        [ h1 [] [ text "Rendre disponible, valoriser et améliorer les données transports" ]
        , h3 [] [ text "transport.beta.gouv.fr c'est quoi ?" ]
        , p [] [ text "C'est la plateforme de diffusion des données ouvertes relatives au transport. Mais c'est aussi la plateforme qui permet à la communauté des diffuseurs et des ré-utilisateurs de se rassembler, de dialoguer, de réfléchir ensemble aux problèmes autour des données transport (qualité, complétude, licences) et de construire les outils pour les résoudre." ]
        , h3 [] [ text "Pourquoi transport.beta.gouv.fr ?" ]
        , p [] [ text "Les données de transport lorsqu’elles existent, sont exposées sur différents portails de diffusion de données ouvertes. On constate souvent un manque d’homogénéité entre les différentes sources ce qui limite la réutilisation des données et freine le déploiement de solutions innovantes sur tout le territoire ou pour tous les utilisateurs. transport.beta.gouv.fr a pour but de résoudre ces différents problèmes et de maximiser les réutilisations pour permettre :" ]
        , ul []
            [ li [] [ text "aux usagers des transports de mieux connaitre l'offre et ainsi de mieux préparer leurs différents déplacements, " ]
            , li [] [ text "que soient expérimentés et proposés de nouveaux services de mobilités pour tous les usagers sur le territoire national mais aussi au niveau européen grâce à la mise en place de portails similaires dans d'autres pays." ]
            ]
        , h3 [] [ text "Comment fonctionne transport.beta.gouv.fr ?" ]
        , p [] [ text "Pour accéder/en savoir plus sur les  jeux de données qui sont exposés sur transport.beta.gouv.fr consultez cette page : http://asdf1234.fr" ]
        , p [] [ text "Pour comprendre comment fonctionne la communauté transport.beta.gouv.fr et la rejoindre consultez cette page : http://qwerty.fr" ]
        , h3 [] [ text "Comment mettre mes données sur transport.beta.gouv.fr ?" ]
        , p [] [ text "Pour que votre jeu de données soit exposé sur transport.beta.gouv.fr consultez cette page : http://delete.me" ]
        , p [] [ text "Nous fonctionnons, comme le portail data.gouv.fr sur le principe du « venez comme vous êtes ». Vous pouvez nous indiquer où trouver vos données (lien vers votre site) et nous nous chargeons de les récupérer, nous fournir des informations sous forme de pdf .. ou bien nous indiquer où sont disponibles vos données déjà consommables." ]
        , h3 [] [ text "Pourquoi beta ?" ]
        , p [] [ text "Ce produit est en phase de construction, il est amené à évoluer, lorsqu'il aura atteint un stade mature nous enleverons le panneau beta." ]
        , h3 [] [ text "Qui sommes nous ?" ]
        , p [] [ text "Nous sommes une start-up d'état de l'incubateur de services numériques : beta.gouv.fr" ]
        ]
