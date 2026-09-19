#lang s-exp syntax/module-reader

attalambda/lang/expander
#:wrapper1 (lambda (read-body)
             (parameterize ([current-readtable #f]
                            [read-accept-reader #f]
                            [read-accept-lang #f]
                            [read-accept-compiled #f])
               (read-body)))
