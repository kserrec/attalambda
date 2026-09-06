#lang racket/base

(require racket/promise
         "../core/map.rkt"
         "list.rkt")

(provide map->string)

(define (map->string value)
  (format "MAP:~a"
          (length
           (list->host-list
            ((force raw-map-entries) value)
            values))))
