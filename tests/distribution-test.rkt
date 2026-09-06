#lang racket/base

(require rackunit
         file/sha1
         racket/file
         racket/list
         racket/path
         racket/runtime-path
         racket/string
         "helpers/fresh-language.rkt")

(define-runtime-path project-root-path "..")
(define project-root
  (simplify-path project-root-path #f))
(define build-script
  (build-path project-root "tooling" "build-linux-distribution.sh"))
(define consumer-script
  (build-path project-root "tooling" "test-linux-distribution.sh"))
(define macos-build-script
  (build-path project-root "tooling" "build-macos-distribution.sh"))
(define macos-consumer-script
  (build-path project-root "tooling" "test-macos-distribution.sh"))
(define windows-build-script
  (build-path project-root "tooling" "build-windows-distribution.ps1"))
(define windows-consumer-script
  (build-path project-root "tooling" "test-windows-distribution.ps1"))
(define workflow-file
  (build-path project-root ".github" "workflows" "tests.yml"))
(define test-runner-script
  (build-path project-root "run-all-tests.sh"))
(define distribution-directory
  (build-path project-root "distribution"))
(define repository-license-file
  (build-path project-root "LICENSE"))
(define bash-executable
  (find-executable-path "bash"))

(check-not-false bash-executable)

(define environment
  (environment-variables-copy (current-environment-variables)))

(define (run-bash arguments)
  (run-command environment bash-executable arguments 20))

(define (check-exact-result result status stdout stderr)
  (check-false (command-result-timed-out? result)
               (result-diagnostic result))
  (check-equal? (command-result-status result)
                status
                (result-diagnostic result))
  (check-equal? (command-result-stdout result)
                stdout
                (result-diagnostic result))
  (check-equal? (command-result-stderr result)
                stderr
                (result-diagnostic result)))

(for ([script (in-list (list build-script
                             consumer-script
                             macos-build-script
                             macos-consumer-script))])
  (check-true (file-exists? script))
  (check-not-false
   (member 'execute (file-or-directory-permissions script)))
  (check-exact-result
   (run-bash (list "-n" (path->string script)))
   0 #"" #""))

(for ([script (in-list (list windows-build-script
                             windows-consumer-script))])
  (check-true (file-exists? script))
  (check-false (link-exists? script)))

(check-exact-result
 (run-bash (list (path->string build-script) "--help"))
 0
 (string->bytes/utf-8
  (string-append
   "Usage:\n"
   "  tooling/build-linux-distribution.sh [--allow-dirty] OUTPUT_DIRECTORY\n"
   "\n"
   "Build the final Linux x86-64 release archive with Racket CS 9.3. The output\n"
   "directory must be outside the source checkout and must not already contain the\n"
   "versioned archive or SHA256SUMS.\n"))
 #"")

(check-exact-result
 (run-bash (list (path->string consumer-script) "--help"))
 0
 (string->bytes/utf-8
  (string-append
   "Usage:\n"
   "  tooling/test-linux-distribution.sh OUTPUT_DIRECTORY\n"
   "\n"
   "Transfer the final Linux release archive and its checksum into\n"
   "a locked-down Ubuntu 24.04 container with no Racket installation, then run the\n"
   "Phase 29 guide, consumer, and relocation acceptance checks.\n"))
 #"")

(check-exact-result
 (run-bash (list (path->string macos-build-script) "--help"))
 0
 (string->bytes/utf-8
  (string-append
   "Usage:\n"
   "  tooling/build-macos-distribution.sh [--allow-dirty] TARGET_IDENTIFIER OUTPUT_DIRECTORY\n"
   "\n"
   "Build one final native macOS release archive with Racket CS 9.3.\n"
   "TARGET_IDENTIFIER must be macos-x86_64 or macos-arm64. OUTPUT_DIRECTORY must\n"
   "already exist outside the source checkout and must not contain the versioned\n"
   "archive or SHA256SUMS.\n"))
 #"")

(check-exact-result
 (run-bash (list (path->string macos-consumer-script) "--help"))
 0
 (string->bytes/utf-8
  (string-append
   "Usage:\n"
   "  tooling/test-macos-distribution.sh OUTPUT_DIRECTORY TARGET_IDENTIFIER\n"
   "\n"
   "Test one transferred final macOS release archive on clean\n"
   "native hardware with no Racket installation or source checkout.\n"
   "TARGET_IDENTIFIER must be macos-x86_64 or macos-arm64.\n"))
 #"")

(check-exact-result
 (run-bash (list (path->string build-script) (path->string project-root)))
 2
 #""
 #"build-linux-distribution: OUTPUT_DIRECTORY must be outside the source checkout\n")

(define (dotenv-name? name)
  (regexp-match? #px"(^|[.])env($|[.])" (string-downcase name)))

(define asset-names
  (sort
   (for/list ([entry (in-list (directory-list distribution-directory))]
              #:unless (dotenv-name? (path->string entry)))
     (path->string entry))
   string<?))
(check-equal?
 asset-names
 '("GETTING_STARTED.md.in"
   "THIRD_PARTY_NOTICES.md.in"
   "UNPUBLISHED-DEVELOPMENT-ARTIFACT.txt"))

(for ([asset-name (in-list asset-names)])
  (define asset-path
    (build-path distribution-directory asset-name))
  (check-true (file-exists? asset-path))
  (check-false (link-exists? asset-path)))

(define build-source
  (file->string build-script))
(check-true (regexp-match? #rx"[+][+]lang attalambda" build-source))
(check-true (regexp-match? #rx"raco_executable.*distribute" build-source))
(check-true (regexp-match? #rx"PLTUSERHOME=" build-source))
(check-true (regexp-match? #rx"gzip -n -9" build-source))
(check-true (regexp-match? #rx"SHA256SUMS" build-source))
(check-true (regexp-match? #rx"final release artifact" build-source))
(check-not-false
 (string-contains? build-source "grep -Eq '@[A-Z_]+@'"))
(check-true (regexp-match? #rx"project_root/LICENSE" build-source))
(check-true
 (regexp-match?
  #rx"516b3a08454709bf111494c92ed260a5c4afb47c91d06efca924b500c89e17ad"
  build-source))
(check-false (regexp-match? #rx"UNPUBLISHED-DEVELOPMENT-ARTIFACT" build-source))

(define consumer-source
  (file->string consumer-script))
(check-true
 (regexp-match?
  #px"ubuntu:24[.]04@sha256:[0-9a-f]{64}"
  consumer-source))
(check-true (regexp-match? #rx"--network none" consumer-source))
(check-true (regexp-match? #rx"--read-only" consumer-source))
(check-not-false
 (string-contains? consumer-source
                   "printf 'consumer_acceptance=passed\\n'"))
(check-not-false
 (string-contains? consumer-source
                   "printf 'guide_workflow=passed\\n'"))
(check-true (regexp-match? #rx"guide custom program" consumer-source))
(check-true (regexp-match? #rx"Artifact status: final release artifact" consumer-source))

(define macos-build-source
  (file->string macos-build-script))
(check-true (regexp-match? #rx"macos-x86_64" macos-build-source))
(check-true (regexp-match? #rx"macos-arm64" macos-build-source))
(check-true (regexp-match? #rx"uname -s.*Darwin" macos-build-source))
(check-true (regexp-match? #rx"[+][+]lang attalambda" macos-build-source))
(check-true (regexp-match? #rx"raco_executable.*distribute" macos-build-source))
(check-true (regexp-match? #rx"mkdir -m 0755 \"[$]artifact_root/lib\"" macos-build-source))
(check-true (regexp-match? #rx"PLTUSERHOME=" macos-build-source))
(check-true (regexp-match? #rx"otool -L" macos-build-source))
(check-true (regexp-match? #rx"lipo -archs" macos-build-source))
(check-true (regexp-match? #rx"gtar" macos-build-source))
(check-true (regexp-match? #rx"gzip -n -9" macos-build-source))
(check-true (regexp-match? #rx"SHA256SUMS" macos-build-source))
(check-true (regexp-match? #rx"final release artifact" macos-build-source))
(check-not-false
 (string-contains? macos-build-source "grep -Eq '@[A-Z_]+@'"))
(check-true (regexp-match? #rx"project_root/LICENSE" macos-build-source))
(check-true
 (regexp-match?
  #rx"516b3a08454709bf111494c92ed260a5c4afb47c91d06efca924b500c89e17ad"
  macos-build-source))
(check-false (regexp-match? #rx"UNPUBLISHED-DEVELOPMENT-ARTIFACT" macos-build-source))
(check-false (regexp-match? #rx"--launcher" macos-build-source))

(define macos-consumer-source
  (file->string macos-consumer-script))
(check-true (regexp-match? #rx"consumer unexpectedly has a racket command" macos-consumer-source))
(check-true (regexp-match? #rx"consumer unexpectedly has a source checkout" macos-consumer-source))
(check-true (regexp-match? #rx"generated-after-packaging[.]attl" macos-consumer-source))
(check-true (regexp-match? #rx"decoy-collections" macos-consumer-source))
(check-true (regexp-match? #rx"/dev/tcp/127[.]0[.]0[.]1" macos-consumer-source))
(check-true (regexp-match? #rx"second relocated path" macos-consumer-source))
(check-true (regexp-match? #rx"sw_vers -productVersion" macos-consumer-source))
(check-not-false
 (string-contains? macos-consumer-source
                   "printf 'consumer_acceptance=passed\\n'"))
(check-not-false
 (string-contains? macos-consumer-source
                   "printf 'guide_workflow=passed\\n'"))
(check-true (regexp-match? #rx"guide custom program" macos-consumer-source))
(check-true (regexp-match? #rx"archive_sha256=" macos-consumer-source))

(define windows-build-source
  (file->string windows-build-script))
(check-true (regexp-match? #rx"windows-x86_64" windows-build-source))
(check-true (regexp-match? #rx"--embed-dlls" windows-build-source))
(check-true (regexp-match? #rx"[+][+]lang.*attalambda" windows-build-source))
(check-true (regexp-match? #rx"'distribute'.*rawDistribution" windows-build-source))
(check-true (regexp-match? #rx"PE32[+] machine 0x8664" windows-build-source))
(check-true (regexp-match? #rx"dumpbin[.]exe" windows-build-source))
(check-true (regexp-match? #rx"Get-AuthenticodeSignature" windows-build-source))
(check-true
 (regexp-match?
  #px"Get-Command git[.]exe[^\n]*[|]\n[ ]*Select-Object -First 1"
  windows-build-source))
(check-true (regexp-match? #rx"1980, 1, 1" windows-build-source))
(check-true (regexp-match? #rx"SHA256SUMS" windows-build-source))
(check-true (regexp-match? #rx"final release artifact" windows-build-source))
(check-not-false
 (string-contains? windows-build-source "-match '@[A-Z_]+@'"))
(check-false (string-contains? windows-build-source ".Contains('@')"))
(check-true (regexp-match? #rx"repository LICENSE" windows-build-source))
(check-true
 (regexp-match?
  #rx"516b3a08454709bf111494c92ed260a5c4afb47c91d06efca924b500c89e17ad"
  windows-build-source))
(check-false (regexp-match? #rx"UNPUBLISHED-DEVELOPMENT-ARTIFACT" windows-build-source))
(check-true (regexp-match? #rx"PLTUSERHOME" windows-build-source))
(check-true (regexp-match? #rx"Remove-Item.*Env:[$]name" windows-build-source))
(check-true (regexp-match? #rx"standardToolchainRoots" windows-build-source))
(check-true (regexp-match? #rx"GetFolderPath[(]'ProgramFiles'" windows-build-source))
(check-true (regexp-match? #rx"Assert-NoForbiddenBuildPaths" windows-build-source))
(check-true (regexp-match? #rx"[$]isolatedUserHome" windows-build-source))
(check-true (regexp-match? #rx"Get-SafeTreeEntries.*-SkipCompiled" windows-build-source))
(check-false (regexp-match? #rx"--launcher" windows-build-source))

(define windows-consumer-source
  (file->string windows-consumer-script))
(check-true (regexp-match? #rx"consumer unexpectedly has a racket command" windows-consumer-source))
(check-true (regexp-match? #rx"consumer unexpectedly has a source checkout" windows-consumer-source))
(check-true (regexp-match? #rx"generated-after-packaging[.]attl" windows-consumer-source))
(check-true (regexp-match? #rx"decoy-collections" windows-consumer-source))
(check-true (regexp-match? #rx"TcpClient" windows-consumer-source))
(check-true (regexp-match? #rx"LocalApplicationData" windows-consumer-source))
(check-true (regexp-match? #rx"relocation_drives=different" windows-consumer-source))
(check-true (regexp-match? #rx"Get-AuthenticodeSignature" windows-consumer-source))
(check-false (regexp-match? #rx"ArgumentList[.]Add[(]'run'[)]" windows-consumer-source))
(check-false (regexp-match? #rx"LASTEXITCODE" windows-consumer-source))
(check-true (regexp-match? #rx"forbidden path marker" windows-consumer-source))
(check-true
 (regexp-match?
  #rx"'github-checkout-segment' = '\\\\a\\\\attalambda\\\\attalambda\\\\'"
  windows-consumer-source))
(check-false
 (regexp-match?
  #rx"'github-checkout-segment' = '\\\\a\\\\'"
  windows-consumer-source))
(check-false (regexp-match? #rx"isolated-registry-segment" windows-consumer-source))
(check-true (regexp-match? #rx"unpackedBytes = [[]int64[]] 0" windows-consumer-source))
(check-true
 (regexp-match?
  #rx"unpacked_regular_file_bytes=[$]unpackedBytes"
  windows-consumer-source))
(check-true (regexp-match? #rx"exit 0" windows-consumer-source))
(check-true (regexp-match? #rx"Assert-ProcessResult.*64" windows-consumer-source))
(check-true (regexp-match? #rx"Assert-ProcessResult.*65" windows-consumer-source))
(check-true (regexp-match? #rx"Assert-ProcessResult.*66" windows-consumer-source))
(check-not-false
 (string-contains? windows-consumer-source
                   "Write-Output 'consumer_acceptance=passed'"))
(check-not-false
 (string-contains? windows-consumer-source
                   "WriteLine('guide_workflow=passed')"))
(check-true (regexp-match? #rx"guide custom program" windows-consumer-source))
(check-true (regexp-match? #rx"Artifact status: final release artifact" windows-consumer-source))

(define workflow-source
  (file->string workflow-file))
(define test-runner-source
  (file->string test-runner-script))

(define (substring-count text substring)
  (length
   (regexp-match* (regexp (regexp-quote substring)) text)))

(check-true
 (regexp-match?
  #px"(?m:^on:\n  push:\n    branches:\n      - main\n  pull_request:\n)"
  workflow-source))
(check-false (regexp-match? #rx"tags:" workflow-source))
(check-not-false
 (string-contains?
  test-runner-source
  "echo \"All ${#test_files[@]} test files passed.\""))
(check-not-false
 (string-contains? workflow-source
                   "./run-all-tests.sh | tee \"$suite_log\""))
(check-not-false
 (string-contains?
  workflow-source
  "[[ \"$(tail -n 1 \"$suite_log\")\" =~ ^All\\ [1-9][0-9]*\\ test\\ files\\ passed[.]$ ]]"))
(check-equal?
 (substring-count workflow-source
                  "| tee \"$consumer_log\"")
 2)
(check-equal?
 (substring-count
  workflow-source
  "[[ \"$(tail -n 1 \"$consumer_log\")\" == \"consumer_acceptance=passed\" ]]")
 2)
(check-not-false
 (string-contains? workflow-source
                   "$consumerCompletion = @("))
(check-not-false
 (string-contains? workflow-source
                   "$consumerCompletion.Count -ne 1 -or"))
(check-not-false
 (string-contains?
  workflow-source
  "$consumerCompletion[0] -cne 'consumer_acceptance=passed'"))
(check-true (regexp-match? #rx"runner: macos-15-intel" workflow-source))
(check-true (regexp-match? #rx"runner: macos-15" workflow-source))
(check-true (regexp-match? #rx"racket-architecture: x64" workflow-source))
(check-true (regexp-match? #rx"racket-architecture: arm64" workflow-source))
(check-true
 (regexp-match?
  #rx"actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a"
  workflow-source))
(check-true
 (regexp-match?
  #rx"actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c"
  workflow-source))
(check-equal? (substring-count workflow-source "retention-days: 1") 2)
(check-equal?
 (substring-count
  workflow-source
 "One day is only an immediate-cleanup failure fallback.")
 2)
(check-equal?
 (substring-count
  workflow-source
  "if: ${{ always() }}")
 2)
(check-true (regexp-match? #rx"actions: write" workflow-source))
(check-true (regexp-match? #rx"gh api --method DELETE" workflow-source))
(check-true (regexp-match? #rx"windows-distribution-build" workflow-source))
(check-true (regexp-match? #rx"windows-distribution-consumer" workflow-source))
(check-true (regexp-match? #rx"macos-distribution-artifact-cleanup" workflow-source))
(check-true (regexp-match? #rx"windows-distribution-artifact-cleanup" workflow-source))
(check-true (regexp-match? #rx"runs-on: windows-2025" workflow-source))
(check-true (regexp-match? #rx"architecture: x64" workflow-source))
(check-true
 (regexp-match?
  #px"(?s:windows-distribution-build:.*Install native Racket.*actions/checkout)"
  workflow-source))
(check-true (regexp-match? #rx"attalambda-windows-x86_64-[$][{][{] github[.]sha [}][}]" workflow-source))

(for ([template-name
       (in-list '("GETTING_STARTED.md.in"
                  "THIRD_PARTY_NOTICES.md.in"))])
  (define template-content
    (file->string (build-path distribution-directory template-name)))
  (check-false (regexp-match? #rx"0[.]2[.]0-dev" template-content))
  (check-false (regexp-match? #rx"0[.]2[.]0-rc[.]1" template-content)))

(define getting-started-template
  (file->string (build-path distribution-directory "GETTING_STARTED.md.in")))
(for ([required-text
       (in-list
        '("## Download, verify, and extract"
          "## Run the first program"
          "## Write an AttaLambda program"
          "## Command results and exit statuses"
          "## Authority and safety"
          "## Release notes"
          "## Known limitations"
          "#lang attalambda"
          "0` | The source loaded and completed"
          "1` | The program explicitly called `(exit 1)`"
          "64` | The command arguments were invalid"
          "65` | The filename"
          "66` | The source was missing"
          "70` | The launcher encountered"
          "does not sandbox programs"
          "write-file` can create, truncate, or replace files"
          "distribution supports Linux x86-64"
          "internal portability evidence, not supported public downloads"
          "Linux x86-64 is the only supported public binary target"))])
  (check-not-false (string-contains? getting-started-template required-text)))

(check-false
 (string-contains?
  getting-started-template
  "archives for Linux x86-64, macOS x86-64, macOS arm64, and Windows x86-64"))

(check-equal?
 (call-with-input-file
     (build-path distribution-directory "THIRD_PARTY_NOTICES.md.in")
   (lambda (input)
     (bytes->hex-string (sha256-bytes input))))
 "516b3a08454709bf111494c92ed260a5c4afb47c91d06efca924b500c89e17ad")

(check-false
 (or (file-exists? (build-path distribution-directory "LICENSE"))
     (link-exists? (build-path distribution-directory "LICENSE"))))

(check-true (file-exists? repository-license-file))
(check-false (link-exists? repository-license-file))
(check-equal?
 (call-with-input-file repository-license-file
   (lambda (input)
     (bytes->hex-string (sha256-bytes input))))
 "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30")
