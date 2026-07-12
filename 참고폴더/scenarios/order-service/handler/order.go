package handler

import (
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type Order struct {
	ID     string  `json:"id"`
	UserID string  `json:"user_id"`
	Amount float64 `json:"amount"`
}

type Handler struct {
	mu     sync.RWMutex
	orders map[string]Order
}

func New() *Handler {
	return &Handler{orders: make(map[string]Order)}
}

func (h *Handler) Create(c *gin.Context) {
	var o Order
	if err := c.ShouldBindJSON(&o); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	o.ID = uuid.NewString()
	h.mu.Lock()
	h.orders[o.ID] = o
	h.mu.Unlock()
	c.JSON(http.StatusCreated, o)
}

func (h *Handler) Get(c *gin.Context) {
	h.mu.RLock()
	o, ok := h.orders[c.Param("id")]
	h.mu.RUnlock()
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	c.JSON(http.StatusOK, o)
}
