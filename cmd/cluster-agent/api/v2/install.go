// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2018 Datadog, Inc.

package v2

import (
	"io/ioutil"
	"net/http"

	"github.com/DataDog/datadog-agent/pkg/clusteragent/custommetrics"
	"github.com/DataDog/datadog-agent/pkg/util/log"
	"github.com/gorilla/mux"
)

const apiHTTPHeaderKey = "DD-Api-Key"

// Install registers v2 API endpoints
func Install(r *mux.Router) {
	r.Use(validationMiddleware)

	r.HandleFunc("series", seriesHandler).Methods("POST")
}

func seriesHandler(w http.ResponseWriter, r *http.Request) {
	defer r.Body.Close()

	body, err := ioutil.ReadAll(r.Body)
	if err != nil {
		log.Errorf("Could not ready body")
		handleError(w, http.StatusInternalServerError)
		return
	}

	if r.Header.Get("Content-Type") != "application/json" {
		handleError(w, http.StatusUnsupportedMediaType)
		return
	}

	if err := custommetrics.DefaultMetricsIntake.Send(body); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.WriteHeader(http.StatusOK)
	return

}

func validationMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		apiKey := r.Header.Get(apiHTTPHeaderKey)
		if apiKey == "" {
			w.Header().Set("WWW-Authenticate", `Bearer realm="Datadog Cluster Agent"`)
			http.Error(w, "no api key provided", http.StatusUnauthorized)
			return
		}

		// TODO(devonboyer): Actually check the API key.

		next.ServeHTTP(w, r)
	})
}

func handleError(w http.ResponseWriter, code int) {
	http.Error(w, http.StatusText(code), code)
}
