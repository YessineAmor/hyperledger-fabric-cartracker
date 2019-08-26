/*
 * Copyright 2018 IBM All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package cartracker

type Repair struct {
	Date             string `json:"date"`
	InsuranceCompany string `json:"insurace_company"`
	Details          string `json:"details"`
}

type Car struct {
	VIN               string   `json:"VIN"`
	Make              string   `json:"make"`
	Model             string   `json:"model"`
	Colour            string   `json:"colour"`
	Owner             string   `json:"owner"`
	ManufacturingDate string   `json:"manufacturing_date"`
	Repairs           []Repair `json:"repairs"`
}
