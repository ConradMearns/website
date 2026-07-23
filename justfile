wip:
    git pull
    git add .
    git commit -m wip
    git push

# goal system — delegate into goal-system/ so verbs work from repo root
goals *ARGS='tree':
    @just --justfile goal-system/justfile --working-directory goal-system {{ARGS}}

tree:
    @just goals tree