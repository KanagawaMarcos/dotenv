;; Basic Config
(setq inhibit-startup-message t) ;; Remove default initial buffer

;; Hide some standard configs
(tool-bar-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(tooltip-mode -1)

 ;; Show line numbers
(global-display-line-numbers-mode t)

;; show current column
(column-number-mode t)

 ;; highlight the current line
(global-hl-line-mode t)

;; Visual sign when top or bottom is hit
(setq visible-bell t)

;; Lateral borders size
(set-fringe-mode 10)

;; Selected text gets replaced
(delete-selection-mode t) 

;; Line Break (wrap mode visual)
(global-visual-line-mode t)

;; Backups
(setq backup-directory-alist `(("." . "~/.dotenv/emacs/backups")))

;; Org Agenda
(custom-set-variables
 '(org-directory "~/dotenv/")
 '(org-agenda-files (list org-directory)))

;; ----------------- INSTALL MELPA---------------------
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
;; Comment/uncomment this line to enable MELPA Stable if desired.  See `package-archive-priorities`
;; and `package-pinned-packages`. Most users will not need or want to do this.
;;(add-to-list 'package-archives '("melpa-stable" . "https://stable.melpa.org/packages/") t)
(package-initialize)
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-enabled-themes '(kanagawa))
 '(custom-safe-themes
   '("4ed5f7e64cf23a10a634fd79b9dbd99be0a874b28d0b8b7a277dfdcf92a335b8" default))
 '(package-selected-packages '(autothemer timu-spacegrey-theme))
 '(warning-suppress-log-types '((comp) (comp) (comp)))
 '(warning-suppress-types '((comp) (comp))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
;;-------------------------------------------------------

;;(add-hook 'after-init-hook 'org-agenda-list)
(global-set-key "\C-ca" 'org-agenda)

;;(load-theme 'solarized-dark t)

(add-to-list 'custom-theme-load-path "~/dotenv/org/")
(load-theme 'kanagawa t)

