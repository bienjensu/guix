(define-module (bienjensu packages hplip)
  #:use-module (gnu packages)
  #:use-module (gnu packages python)
  #:use-module (gnu packages cups)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages libusb)
  #:use-module (gnu packages image)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages qt)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages scanner)
  #:use-module (gnu packages base)
  #:use-module (gnu packages pkg-config)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (srfi srfi-1))

(define-public hplip-nf
  (package
    (name "hplip-nf")
    (version "3.23.5")
    (source (origin
              (method url-fetch)
              (uri (string-append "mirror://sourceforge/hplip/hplip/" version
                                  "/hplip-" version ".tar.gz"))
              (sha256
               (base32
                "1j6bjn4zplxl7w15xrc1v5l3p9a0x0345756ahvgq8mi97bmx3pn"))
              (modules '((guix build utils)))
              ;; (snippet
              ;;  '(begin
              ;;     ;; Delete non-free blobs: .so files, pre-compiled
              ;;     ;; 'locatedriver' executable, etc.
              ;;     (for-each delete-file
              ;;               (find-files "."
              ;;                           (lambda (file stat)
              ;;                             (elf-file? file))))

              ;;     ;; Now remove some broken references to them.
              ;;     (delete-file "prnt/hpcups/ImageProcessor.h")
              ;;     (substitute* "Makefile.in"
              ;;       ((" -lImageProcessor ") " ")
              ;;       ;; Turn shell commands inside an if…fi into harmless no-ops.
              ;;       (("^(\\@HPLIP_BUILD_TRUE\\@[[:blank:]]*).*libImageProcessor.*"
              ;;         _ prefix)
              ;;        (string-append prefix ": ; \\\n"))
              ;;       ;; Remove the lines adding file targets altogether.
              ;;       (("^\\@FULL_BUILD_TRUE\\@.*libImageProcessor.*")
              ;;        ""))

              ;;     ;; Install binaries under libexec/hplip instead of
              ;;     ;; share/hplip; that'll at least ensure they get stripped.
              ;;     ;; It's not even clear that they're of any use though...
              ;;     (substitute* "Makefile.in"
              ;;       (("^dat2drvdir =.*")
              ;;        "dat2drvdir = $(pkglibexecdir)\n")
              ;;       (("^locatedriverdir =.*")
              ;;        "locatedriverdir = $(pkglibexecdir)\n"))))
              ))
    (outputs (list "out" "ppd"))
    (build-system gnu-build-system)
    (arguments
     (list
      #:imported-modules `((guix build python-build-system)
                           ,@%gnu-build-system-modules)
      #:modules '((guix build gnu-build-system)
                  (guix build utils)
                  ((guix build python-build-system) #:prefix python:))
      #:configure-flags
      #~(list
         ;; "--disable-imageProcessor-build"
         "--disable-network-build"
         (string-append "--prefix=" #$output)
         (string-append "--sysconfdir=" #$output "/etc")
         (string-append "LDFLAGS=-Wl,-rpath=" #$output "/lib")
         ;; Disable until mime.types merging works (FIXME).
         "--disable-fax-build"
         "--enable-new-hpcups"
         ;; TODO add foomatic drv install eventually.
         ;; TODO --enable-policykit eventually.
         (string-append "--with-cupsfilterdir=" #$output
                        "/lib/cups/filter")
         (string-append "--with-cupsbackenddir=" #$output
                        "/lib/cups/backend")
         (string-append "--with-hpppddir=" #$output:ppd "/share/ppd/HP")
         (string-append "--with-icondir=" #$output "/share/applications")
         (string-append "--with-systraydir=" #$output "/etc/xdg")
         "--enable-qt5"
         "--disable-qt4")
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'fix-hard-coded-file-names
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let ((out #$output)
                    ;; FIXME: use merged ppds (I think actually only
                    ;; drvs need to be merged).
                    (cupsdir #$(this-package-input "cups-minimal")))
                (substitute* (find-files "." "\\.py$")
                  ;; Refer to the correct default configuration file name.
                  (("/etc/hp/hplip.conf")
                   (string-append out "/etc/hp/hplip.conf")))
                (substitute* "base/g.py"
                  (("'/usr/share;[^']*'")
                   (string-append "'" cupsdir "/share'"))
                  (("'/etc/hp/hplip.conf'")
                   (string-append "'" out "/etc/hp/hplip.conf" "'")))

                (substitute* "Makefile.in"
                  (("[[:blank:]]check-plugin\\.py[[:blank:]]") " ")
                  ;; FIXME Use beginning-of-word in regexp.
                  (("[[:blank:]]plugin\\.py[[:blank:]]") " ")
                  (("/usr/include/libusb-1.0")
                   (search-input-directory inputs "/include/libusb-1.0"))
                  (("hplip_statedir =.*$")
                   ;; Don't bail out while trying to create
                   ;; /var/lib/hplip.  We can safely change its value
                   ;; here because it's hard-coded in the code anyway.
                   "hplip_statedir = $(prefix)\n")
                  (("hplip_confdir = /etc/hp")
                   ;; This is only used for installing the default config.
                   (string-append "hplip_confdir = " out "/etc/hp"))
                  (("halpredir = /usr/share/hal/fdi/preprobe/10osvendor")
                   ;; We don't use hal.
                   (string-append "halpredir = " out
                                  "/share/hal/fdi/preprobe/10osvendor"))
                  (("rulesdir = /etc/udev/rules.d")
                   ;; udev rules will be merged by base service.
                   (string-append "rulesdir = " out "/lib/udev/rules.d"))
                  (("rulessystemdir = /usr/lib/systemd/system")
                   ;; We don't use systemd.
                   (string-append "rulessystemdir = " out "/lib/systemd/system"))
                  (("/etc/sane.d")
                   (string-append out "/etc/sane.d"))))))
          (add-after 'install 'install-models-dat
            (lambda* (#:key outputs #:allow-other-keys)
              (install-file "data/models/models.dat"
                            (string-append #$output "/share/hplip/data/models"))))
          (add-after 'install 'wrap-binaries
            ;; Scripts in /bin are all symlinks to .py files in /share/hplip.
            ;; Symlinks are immune to the Python build system's 'WRAP phase,
            ;; and the .py files can't be wrapped because they are reused as
            ;; modules.  Replacing the symlinks in /bin with copies and
            ;; wrapping them also doesn't work (“ModuleNotFoundError:
            ;; No module named 'base'”).  Behold: a custom WRAP-PROGRAM.
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (bin (string-append out "/bin"))
                     (site (python:site-packages inputs outputs)))
                (with-directory-excursion bin
                  (for-each (lambda (file)
                              (let ((target (readlink file)))
                                (delete-file file)
                                (with-output-to-file file
                                  (lambda _
                                    (format #t
                                            "#!~a~@
                                           export GUIX_PYTHONPATH=\"~a:~a\"~@
                                           exec -a \"$0\" \"~a/~a\" \"$@\"~%"
                                            (which "bash")
                                            site
                                            (getenv "GUIX_PYTHONPATH")
                                            bin target)))
                                (chmod file #o755)))
                            (find-files "." (lambda (file stat)
                                              (eq? 'symlink (stat:type stat))))))))))))
    ;; Note that the error messages printed by the tools in the case of
    ;; missing dependencies are often downright misleading.
    ;; TODO: hp-toolbox still fails to start with:
    ;;   from dbus.mainloop.pyqt5 import DBusQtMainLoop
    ;;   ModuleNotFoundError: No module named 'dbus.mainloop.pyqt5'
    (native-inputs (list perl pkg-config))
    (inputs
     (list cups-minimal
           dbus
           libjpeg-turbo
           libusb
           python
           python-dbus
           python-pygobject
           python-pyqt
           python-wrapper
           sane-backends-minimal
           zlib))
    (home-page "https://developers.hp.com/hp-linux-imaging-and-printing")
    (synopsis "HP printer drivers nonfree")
    (description
     "Hewlett-Packard printer drivers and PostScript Printer Descriptions
(@dfn{PPD}s). Fixed to add nonfree content.")
    ;; The 'COPYING' file lists directories where each of these 3 licenses
    ;; applies.
    (license (list license:gpl2+ license:bsd-3 license:expat))))

(define-public hplip-plugin-nf
  (package
    (inherit hplip-nf)
    (name "hplip-plugin-nf")
    (description "Hewlett-Packard printer drivers with nonfree plugin.")
    (source (origin
              (inherit (package-source hplip-nf))))
    (inputs (package-inputs hplip-nf))
    (native-inputs
     (append
      `(("hplip-plugin"
         ,(origin
            (method url-fetch)
            (uri (string-append "https://developers.hp.com/sites/default/files/hplip-"
                                (package-version hplip-nf) "-plugin.run"))
            ;; TODO: Since this needs to be updated on every update to Guix's
            ;; hplip in order to build, might be better to decouple this
            ;; package from hplip.  In the meantime, update this hash when
            ;; hplip is updated in Guix.
            (sha256
             (base32
              "1396d9skaq5c5vxxi331nc81yhm9daws7awq0rcn1faq89mvygps")))))
      (package-native-inputs hplip-nf)))
    (arguments
     (substitute-keyword-arguments (package-arguments hplip-nf)
       ((#:phases ph)
        #~(modify-phases #$ph
           (replace 'fix-hard-coded-file-names
             (lambda* (#:key inputs outputs #:allow-other-keys)
               (let ((out (assoc-ref outputs "out"))
                     ;; FIXME: use merged ppds (I think actually only
                     ;; drvs need to be merged).
                     (cupsdir (assoc-ref inputs "cups-minimal")))
                 (substitute* "base/g.py"
                   (("'/usr/share;[^']*'")
                    (string-append "'" cupsdir "/share'"))
                   (("'/etc/hp/hplip.conf'")
                    (string-append "'" out
                                   "/etc/hp/hplip.conf" "'"))
                   (("/var/lib/hp")
                    (string-append
                     out
                     "/var/lib/hp")))

                 (substitute* "Makefile.in"
                   (("[[:blank:]]check-plugin\\.py[[:blank:]]") " ")
                   ;; FIXME Use beginning-of-word in regexp.
                   (("[[:blank:]]plugin\\.py[[:blank:]]") " ")
                   (("/usr/include/libusb-1.0")
                    (string-append (assoc-ref inputs "libusb")
                                   "/include/libusb-1.0"))
                   (("hplip_statedir =.*$")
                    ;; Don't bail out while trying to create
                    ;; /var/lib/hplip.  We can safely change its value
                    ;; here because it's hard-coded in the code anyway.
                    "hplip_statedir = $(prefix)/var/lib/hp\n")
                   (("hplip_confdir = /etc/hp")
                    ;; This is only used for installing the default config.
                    (string-append "hplip_confdir = " out
                                   "/etc/hp"))
                   (("halpredir = /usr/share/hal/fdi/preprobe/10osvendor")
                    ;; We don't use hal.
                    (string-append "halpredir = " out
                                   "/share/hal/fdi/preprobe/10osvendor"))
                   (("rulesdir = /etc/udev/rules.d")
                    ;; udev rules will be merged by base service.
                    (string-append "rulesdir = " out
                                   "/lib/udev/rules.d"))
                   (("rulessystemdir = /usr/lib/systemd/system")
                    ;; We don't use systemd.
                    (string-append "rulessystemdir = " out
                                   "/lib/systemd/system"))
                   (("/etc/sane.d")
                    (string-append out "/etc/sane.d")))

                 (substitute* "common/utils.h"
                   (("/var/lib/hp")
                    (string-append
                     out
                     "/var/lib/hp"))))))
           (add-after 'install-models-dat 'install-plugins
             (lambda* (#:key outputs system inputs #:allow-other-keys)
               (let* ((out (assoc-ref outputs "out"))
                      (state-dir (string-append out "/var/lib/hp"))
                      (hp-arch (assoc-ref
                                '(("i686-linux" . "x86_32")
                                  ("x86_64-linux" . "x86_64")
                                  ("armhf-linux" . "arm32")
                                  ("aarch64-linux" . "aarch64"))
                                system)))
                 (unless hp-arch
                   (error (string-append
                           "HPLIP plugin not supported on "
                           system)))
                 (invoke "sh" (assoc-ref inputs "hplip-plugin")
                         "--noexec" "--keep")
                 (chdir "plugin_tmp")
                 (install-file "plugin.spec"
                               (string-append out "/share/hplip/"))

                 (for-each
                  (lambda (file)
                    (install-file
                     file
                     (string-append out "/share/hplip/data/firmware")))
                  (find-files "." "\\.fw.gz$"))

                 (install-file "license.txt"
                               (string-append out "/share/hplip/data/plugins"))
                 (mkdir-p
                  (string-append out "/share/hplip/prnt/plugins"))
                 (for-each
                  (lambda (type plugins)
                    (for-each
                     (lambda (plugin)
                       (let ((file (string-append plugin "-" hp-arch ".so"))
                             (dir (string-append out "/share/hplip/"
                                                 type "/plugins")))
                         (install-file file dir)
                         (chmod (string-append dir "/" file) #o755)
                         (symlink (string-append dir "/" file)
                                  (string-append dir "/" plugin ".so"))))
                     plugins))
                  '("prnt" "scan")
                  '(("lj" "hbpl1")
                    ("bb_soap" "bb_marvell" "bb_soapht" "bb_escl")))
                 (mkdir-p state-dir)
                 (call-with-output-file
                     (string-append state-dir "/hplip.state")
                   (lambda (port)
                     (simple-format port "[plugin]
installed=1
eula=1
version=~A
" #$(package-version hplip-nf))))

                 (substitute* (string-append out "/etc/hp/hplip.conf")
                   (("/usr") out)))))))))))
