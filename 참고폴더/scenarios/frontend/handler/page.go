package handler

import (
	"html/template"
	"net/http"
)

type Handler struct{ tmpl *template.Template }

func New(glob string) (*Handler, error) {
	t, err := template.ParseGlob(glob)
	if err != nil {
		return nil, err
	}
	return &Handler{tmpl: t}, nil
}

func (h *Handler) Index(w http.ResponseWriter, _ *http.Request) {
	_ = h.tmpl.ExecuteTemplate(w, "index.html", map[string]string{"Title": "EKS Study Demo"})
}
