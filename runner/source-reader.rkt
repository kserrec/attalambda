#lang racket/base

;; Private source tooling. This never evaluates source or reads program answers.
(require (only-in racket/string string-prefix?))

(provide (struct-out source-buffer) (struct-out source-command)
         parse-source-buffer parse-source-entry read-source-entry source-ready?)

(struct source-buffer (status text forms message line column) #:transparent)
(struct source-command (name argument text) #:transparent)

(define (parse-source-buffer source content
                             #:line [line 1] #:column [column 0]
                             #:position [position 1])
  (with-handlers ([exn:fail:contract?
                   (lambda (_)
                     (source-buffer 'error #f '() "source is not valid UTF-8"
                                    line column))])
    (define text
      (if (bytes? content) (bytes->string/utf-8 content #f) content))
    (define input (open-input-string text))
    (port-count-lines! input)
    (set-port-next-location! input line column position)
    (define (failure-result failure status)
      (define locations (exn:fail:read-srclocs failure))
      (define location (and (pair? locations) (car locations)))
      (define-values (end-line end-column end-position) (port-next-location input))
      (source-buffer status text '()
                     (if (eq? status 'incomplete)
                         "unfinished source entry"
                         "source could not be read; check delimiters and reader syntax")
                     (or (and location (srcloc-line location)) end-line line)
                     (or (and location (srcloc-column location)) end-column column)))
    (dynamic-wind
     void
     (lambda ()
       (call-with-default-reading-parameterization
        (lambda ()
          (parameterize ([current-readtable #f]
                         [read-accept-reader #f]
                         [read-accept-lang #f]
                         [read-accept-compiled #f])
            (with-handlers ([exn:fail:read:eof?
                             (lambda (failure) (failure-result failure 'incomplete))]
                            [exn:fail:read?
                             (lambda (failure) (failure-result failure 'error))])
              (let loop ([forms '()])
                (define form (read-syntax source input))
                (if (eof-object? form)
                    (source-buffer (if (null? forms) 'empty 'complete)
                                   text (reverse forms) #f #f #f)
                    (loop (cons form forms)))))))))
     (lambda () (close-input-port input)))))

(define (trim-command-space text)
  (define size (string-length text))
  (define start
    (or (for/first ([index (in-range size)]
                    #:unless (char-whitespace? (string-ref text index))) index)
        size))
  (define end
    (or (for/first ([index (in-range (sub1 size) (sub1 start) -1)]
                    #:unless (char-whitespace? (string-ref text index))) (add1 index))
        start))
  (substring text start end))

(define (parse-source-entry source content)
  (define parsed (parse-source-buffer source content))
  (define text (source-buffer-text parsed))
  (define trimmed (and text (trim-command-space text)))
  (cond
    [(and trimmed (string-prefix? trimmed ":"))
     (define separator
       (or (for/first ([index (in-range 1 (string-length trimmed))]
                       #:when (char-whitespace? (string-ref trimmed index))) index)
           (string-length trimmed)))
     (define name (string->symbol (substring trimmed 1 separator)))
     (define tail (trim-command-space (substring trimmed separator)))
     (define arguments (parse-source-buffer source tail))
     (define forms (source-buffer-forms arguments))
     (define (invalid reason) (source-buffer 'error text '() reason 1 0))
     (cond
       [(memq name '(help names reset quit))
        (if (eq? (source-buffer-status arguments) 'empty)
            (source-command name #f text)
            (invalid "this command takes no arguments"))]
       [(eq? name 'echo)
        (if (and (eq? (source-buffer-status arguments) 'complete)
                 (= (length forms) 1) (identifier? (car forms))
                 (memq (syntax-e (car forms)) '(on off)))
            (source-command name (eq? (syntax-e (car forms)) 'on) text)
            (invalid "expected :echo on or :echo off"))]
       [(eq? name 'load)
        (if (and (string-prefix? tail "\"")
                 (eq? (source-buffer-status arguments) 'complete)
                 (= (length forms) 1) (string? (syntax-e (car forms))))
            (source-command name (syntax-e (car forms)) text)
            (invalid "expected :load followed by exactly one quoted path string"))]
       [else (invalid "unknown command; use :help")])]
    [else parsed]))

(define (source-ready? text)
  (define result (parse-source-entry 'repl text))
  (not (and (source-buffer? result)
            (eq? (source-buffer-status result) 'incomplete))))

;; Preserve every collected byte, including CRLF and a final unterminated line.
;; Stop at LF without looking ahead into the answer. Terminal line discipline
;; supplies LF; redirected bare CR remains source whitespace within that line.
(define (read-source-line input)
  (define output (open-output-bytes))
  (let loop ()
    (define byte (read-byte input))
    (cond
      [(eof-object? byte)
       (define content (get-output-bytes output))
       (if (zero? (bytes-length content)) eof content)]
      [else
       (write-byte byte output)
       (if (= byte 10) (get-output-bytes output) (loop))])))

(define (read-source-entry input source #:continue [continue void])
  (let loop ([content #""] [pending #f])
    (define line (read-source-line input))
    (cond
      [(eof-object? line)
       (if pending (struct-copy source-buffer pending [status 'unfinished-eof]) eof)]
      [else
       (define next (bytes-append content line))
       (define result (if pending
                          (parse-source-buffer source next)
                          (parse-source-entry source next)))
       (if (and (source-buffer? result)
                (eq? (source-buffer-status result) 'incomplete))
           (begin (continue) (loop next result))
           result)])))
