# Download https://github.com/JohnnyMorganz/wally-package-types
# Allows types to be passed through the pointer modules generated by wally
rojo sourcemap default.project.json --output sourcemap.json
wally-package-types --sourcemap sourcemap.json Packages/