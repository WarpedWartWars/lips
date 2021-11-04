(define (require url)
  "Load JS or script tag"
  (new Promise (lambda (resolve)
                 (if (null? (match #/.css$/ url))
                     ((. $ 'getScript) url resolve)
                     (let ((link ($ (concat "<link type=\"text/css\" rel=\"stylesheet\" href=\""
                                             url
                                             "\"/>"))))
                       (--> link (on "load" resolve) (appendTo "head")))))))

(define $ jQuery)
;; (require "https://unpkg.com/alasql@0.4.11/dist/alasql.min.js")

(require "../examples/prism.js")

(define (prn x)
  (print x)
  x)

;; setup isomorphic-git and global fs methods as functions
(define fs (let* ((fs (new LightningFS "fs"))
                  (pfs fs.promises))
             (git.plugins.set "fs" fs)
             pfs))

(define (new-repo dir)
  "Prepare new git repo with base app"
  (let ((dir (if (null? (match #/^\// dir)) (concat "/" dir) dir)))
    (if (not (directory? dir))
        (begin
          (fs.mkdir dir)
          (git.init (object :dir dir))))))

(define (have-type type x)
  (try (eq? (. (fs.stat x) 'type) type)
       (catch (e) false)))

(define directory? (curry have-type "dir"))
(define file? (curry have-type "file"))


(define (resiter-service-worker file)
  (let* ((scope (replace #/\/[^\/]+$/ "/" (. location 'pathname)))
         (register (. navigator 'serviceWorker 'register)))
    (register "sw.js" (object :scope scope))))

;; registering service worker
(ignore (try (let ((req (resiter-service-worker "sw.js")))
               (set-global! req)
               (req.addEventListener "updatefound" (lambda ()
                                                     (let ((msg "A new service worker is being installed"))
                                                       (console.log msg))))
               (console.log (concat "Registration succeeded. Scope is " req.scope)))
             (catch (e)
                    (console.log (concat "Registration failed " (repr e))))))

(define refresh-editors (debounce (lambda ()
                                    (for-each (lambda (editor)
                                                (editor.refresh))
                                              (list html-editor css-editor lips-editor)))
                                  40))

(--> ($ ".container")
     (split (object :percent true
                    :orientation "horizontal"
                    :limit 10
                    :onDrag refresh-editors
                    :position #("50%" "30%")))
     (find ".panels")
     (split (object :percent true
                    :orientation "vertical"
                    :onDrag refresh-editors
                    :limit 10
                    :position #("33%" "33%"))))


(define (editor selector mode)
  (--> CodeMirror (fromTextArea (--> document (querySelector selector))
                                (object :mode mode
                                        :theme "twilight"
                                        :scrollbarStyle "simple"
                                        :lineWrapping true
                                        :matchBrackets true
                                        :lineNumbers true))))

(define css-editor (editor ".css .code" "css"))
(define lips-editor (editor ".lips .code" "scheme"))
(define html-editor (editor ".html .code" "htmlmixed"))

;; terminal function defined in ../examples/terminal.js
(define term (terminal (object :selector ($ ".term") :lips lips :name "lips-editor")))
(--> (. $ 'terminal) (syntax "scheme"))



(--> ($ "body") (removeClass "cloak"))

(define-macro (let** list . body)
  `(apply (lambda ,(map car list) ,@body) (list* ,@(map cadr list))))

(define (ajax path)
  (--> (fetch path) (text)))

(define (new-app dir)
  (let ((helpers.lips (ajax "../examples/helpers.lips"))
        (index.html (ajax "template/index.html"))
        (app.lips (ajax "template/app.lips")))
    (fs.writeFile (join "/" (list dir "index.html")) index.html)
    (fs.writeFile (join "/" (list dir "app.lips")) app.lips)
    (fs.writeFile (join "/" (list dir "style.css")) "")
    (fs.writeFile (join "/" (list dir "helpers.lips")) helpers.lips)
    (--> html-editor (setValue index.html))
    (--> lips-editor (setValue app.lips))))

(define struct `((,css-editor . "style.css")
                 (,html-editor . "index.html")
                 (,lips-editor . "app.lips")))

(define (load-into-editor editor filename)
  (--> editor (setValue (if (file? filename) (readFile filename) ""))))

(define (editor-to-file editor file)
  (fs.writeFile file (--> editor (getValue))))

(define (do-editors fn name)
  (for-each (lambda (pair)
              (if (not (directory? name))
                  (error (concat name " is not directory"))
                  (let ((path (join "/" (list name (cdr pair)))))
                    (fn (car pair) path))))
            struct))

(define load-app (curry do-editors load-into-editor))
(define save-app (curry do-editors editor-to-file))

(define (run-app name)
  (let* (($iframe ($ ".preview iframe"))
         (src (--> $iframe (val))))
    (if (null? (match (new RegExp (concat "__browserfs__/" name)) src))
        (--> $iframe (attr "src" (concat "./__browserfs__/" name "/")))
        (refresh-src $iframe))))


(define (readFile path)
  (let ((d (new TextDecoder "utf-8")))
    (--> d (decode (fs.readFile path)))))

(define-macro (.on $element event . code)
  `(--> ,$element (on ,event (lambda ()
                              ,@code))))

(define (refresh-src $node)
  (let* ((old (--> $node (attr "src")))
         (now (--> Date (now)))
         (new-src (if (null? (match #/\?/ old))
                      (concat old "?" now)
                      (replace #/[^?]*$/ now))))
    (--> $node (attr "src" new-src))))


(define (lower string)
  (--> string (toLowerCase)))

(define (upper string)
  (--> string (toUpperCase)))


(let* ((apps (array->list (fs.readdir "/")))
       ($save ($ "#save"))
       ($iframe ($ ".preview iframe"))
       ($run ($ "#run"))
       ($download ($ "#download"))
       ($apps ($ "#apps"))
       (save (lambda ()
               (save-app (concat "/" (--> $apps (val)))))))
  (--> $apps (empty))
  (.on $apps "change" (load-app (concat "/" (--> $apps (val)))))
  (.on $save "click" (save))
  (.on $run "click" (run-app (--> $apps (val))))
  (.on $download "click" (let ((name (--> $apps (val))))
                           (make-zip (concat "/" name) name)))
  (--> ($ document) (on "keydown" (lambda (e)
                                    (log (and (eq? (upper (. e 'key)) "S") (. e 'ctrlKey)))
                                    (if (and (eq? (upper (. e 'key)) "S") (. e 'ctrlKey))
                                        (begin
                                          (save)
                                          (--> e (preventDefault)))))))
  (for-each (lambda (app)
              (--> $apps (append (concat "<option>" app "</option>"))))
            apps)
  (--> $apps (trigger "change")))


(define (commit dir)
  (if (directory? dir)
      (let ((now (string (--> Date (now)))))
        (for-each (lambda (file)
                    (print file)
                    (if (not (eq? file ".git"))
                        (git.add (object :dir dir :filepath file))))
                  (array->list (fs.readdir dir)))
        (git.commit (object :dir dir
                            :author (:name "Anonymous" :email "mail@example.com")
                            :message (concat "save lips editor " now))))))



(define (traverse-directory directory-first dir callback)
  (let ((files (array->list (fs.readdir dir))))
    (if directory-first
        (callback "directory" dir))
    (for-each (lambda (name)
                (if (not (match #/^\.{1.2}/ name))
                    (let ((path (concat dir "/" name)))
                      (if (directory? path)
                          (traverse-directory directory-first path callback)
                          (callback "file" path)))))
              files)
    (if (not directory-first)
        (callback "directory" dir))))

(define (make-zip dir zip-name)
   (if (directory? dir)
       (let* ((zip (new JSZip))
              (root (--> zip (folder zip-name)))
              (re (new RegExp (concat "^" dir "/?")))
              (directories nil)
              (run (lambda (stat filepath)
                     (let ((rel-path (replace re "" filepath)))
                       (if (eq? stat "directory")
                           (set! directories (cons (cons rel-path
                                                         (--> root (folder rel-path)))
                                                   directories))
                           ;; we use array here
                           (let* ((parts (--> rel-path (split "/")))
                                  (filename (--> parts (pop)))
                                  (dir (--> parts (join "/"))))
                             ;;(--> console (log (object :dir dir :filename filename)))
                             (let ((content (fs.readFile filepath))
                                   (pair (assoc dir directories)))
                               (--> (if (pair? pair)
                                        (cdr pair)
                                        root)
                                    (file filename content)))))))))
         (traverse-directory true dir run)
         (download-zip (concat zip-name ".zip") zip))))

(define (download-zip name zip)
  (let* ((uint8array (--> zip (generateAsync (object :type "uint8array"))))
         (blob (new Blob (list->array (list uint8array))))
         (reader (new FileReader)))
    (set-obj! reader 'onload (lambda (event)
                               (let* (($a ($ "<a>download</a>")))
                                 (--> $a
                                      (attr "href" (. event 'target 'result))
                                      (attr "download" name)
                                      (appendTo "body")
                                      (get 0)
                                      (click))
                                 (timer 100 (--> $a (remove))))))
    (--> reader (readAsDataURL blob))))
