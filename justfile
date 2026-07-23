wip:
    git pull
    git add .
    git commit -m wip
    git push

# goal system — delegate into goal-system/ so verbs work from repo root.
# bare `just goals` shows this repo's subgraph; `just tree` shows everything.
goals *ARGS='tree website':
    @just --justfile goal-system/justfile --working-directory goal-system {{ARGS}}

tree *FILTER:
    @just goals tree {{FILTER}}