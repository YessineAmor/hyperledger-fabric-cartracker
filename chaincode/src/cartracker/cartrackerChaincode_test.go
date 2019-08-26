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

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/hyperledger/fabric/core/chaincode/shim"
)

func checkInit(t *testing.T, stub *shim.MockStub, args [][]byte) {
	res := stub.MockInit("1", args)
	if res.Status != shim.OK {
		fmt.Println("Init failed", string(res.Message))
		t.FailNow()
	}
}

func checkState(t *testing.T, stub *shim.MockStub, name string, value string) {
	bytes := stub.State[name]
	if bytes == nil {
		fmt.Println("State", name, "failed to get value")
		t.FailNow()
	}
	if string(bytes) != value {
		fmt.Println("State value", name, "was", string(bytes), "and not", value, "as expected")
		t.FailNow()
	}
}

func checkBadQuery(t *testing.T, stub *shim.MockStub, function string, name string) {
	res := stub.MockInvoke("1", [][]byte{[]byte(function), []byte(name)})
	if res.Status == shim.OK {
		fmt.Println("Query", name, "unexpectedly succeeded")
		t.FailNow()
	}
}

func checkBadInvoke(t *testing.T, stub *shim.MockStub, args [][]byte) {
	res := stub.MockInvoke("1", args)
	if res.Status == shim.OK {
		fmt.Println("Invoke", args, "unexpectedly succeeded")
		t.FailNow()
	}
}

func checkInvoke(t *testing.T, stub *shim.MockStub, args [][]byte) {
	res := stub.MockInvoke("1", args)
	if res.Status != shim.OK {
		fmt.Println("Invoke", args, "failed", string(res.Message))
		t.FailNow()
	}
}

func TestCreateCar(t *testing.T) {
	ctc := new(CarTrackerChaincode)
	ctc.testMode = true
	stub := shim.NewMockStub("Car Tracker", ctc)

	vin := "SHHFK2760CU003289"
	make := "Honda"
	model := "Civic"
	colour := "Black"
	owner := "Honda"
	repairs := []Repair{}
	manufacturingDate := time.Now().Format(time.UnixDate)
	// No need to pass repairs. The car will be created with an empty repairs array in createCar function
	checkInvoke(t, stub, [][]byte{[]byte("createCar"), []byte(vin), []byte(make), []byte(model),
		[]byte(colour), []byte(owner), []byte(manufacturingDate)})
	car := Car{vin, make, model, colour, owner, manufacturingDate, repairs}
	carAsBytes, _ := json.Marshal(car)

	checkState(t, stub, vin, string(carAsBytes))
}

func TestAddRepairWork(t *testing.T) {
	ctc := new(CarTrackerChaincode)
	ctc.testMode = true
	stub := shim.NewMockStub("Car Tracker", ctc)

	vin := "SHHFK2760CU003289"
	make := "Honda"
	model := "Civic"
	colour := "Black"
	owner := "Honda"
	repairs := []Repair{}
	manufacturingDate := time.Now().Format(time.UnixDate)
	// No need to pass repairs. The car will be created with an empty repairs array in createCar function
	checkInvoke(t, stub, [][]byte{[]byte("createCar"), []byte(vin), []byte(make), []byte(model),
		[]byte(colour), []byte(owner), []byte(manufacturingDate)})
	car := Car{vin, make, model, colour, owner, manufacturingDate, repairs}
	carAsBytes, _ := json.Marshal(car)

	checkState(t, stub, vin, string(carAsBytes))

	repairDate := time.Now().Format(time.UnixDate)
	insuranceCompanyMSP := "InsuranceCompanyOrgMSP"
	repairDetails := "Broken windhshield"
	repairs = append(repairs, Repair{repairDate, insuranceCompanyMSP, repairDetails})
	car.Repairs = repairs
	checkInvoke(t, stub, [][]byte{[]byte("addRepairWork"), []byte(vin), []byte(repairDate),
		[]byte(insuranceCompanyMSP), []byte(repairDetails)})
	carWithRepairAsBytes, _ := json.Marshal(car)
	checkState(t, stub, vin, string(carWithRepairAsBytes))

}
