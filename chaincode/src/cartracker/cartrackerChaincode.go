package cartracker

import (
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric/core/chaincode/shim"
	pb "github.com/hyperledger/fabric/protos/peer"
)

// CarTrackerChaincode implementation
type CarTrackerChaincode struct {
	testMode bool
}

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

func (c *CarTrackerChaincode) Init(stub shim.ChaincodeStubInterface) pb.Response {
	return shim.Success(nil)
}

func (c *CarTrackerChaincode) Invoke(stub shim.ChaincodeStubInterface) pb.Response {
	// Retrieve the requested chaincde function and arguments
	function, args := stub.GetFunctionAndParameters()
	// Route to the appropriate handler function to interact with the ledger appropriately
	if function == "queryCar" {
		return c.queryCar(stub, args)
	} else if function == "initLedger" {
		return c.initLedger(stub)
	} else if function == "createCar" {
		return c.createCar(stub, args)
	} else if function == "queryAllCars" {
		return c.queryAllCars(stub)
	} else if function == "changeCarOwner" {
		return c.changeCarOwner(stub, args)
	} else if function == "addRepairWork" {
		return c.addRepairWork(stub, args)
	} else if function == "getCarHistory" {
		return c.getCarHistory(stub, args)
	}

	return shim.Error("Invalid chaincode function name.")
}

func (c *CarTrackerChaincode) initLedger(stub shim.ChaincodeStubInterface) pb.Response {
	return shim.Success(nil)
}
func (c *CarTrackerChaincode) queryAllCars(stub shim.ChaincodeStubInterface) pb.Response {
	return shim.Success(nil)
}
func (c *CarTrackerChaincode) changeCarOwner(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	return shim.Success(nil)
}

func (c *CarTrackerChaincode) createCar(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	var car = Car{VIN: args[0], Make: args[1], Model: args[2], Colour: args[3],
		Owner: args[4], ManufacturingDate: args[5], Repairs: []Repair{}}
	carAsBytes, _ := json.Marshal(car)
	stub.PutState(args[0], carAsBytes)

	return shim.Success(nil)
}
func (c *CarTrackerChaincode) getCarHistory(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	if len(args) != 1 {
		return shim.Error("Incorrect number of arguments. Expecting 1")
	}
	carAsBytes, _ := stub.GetState(args[0])
	if carAsBytes == nil {
		return shim.Error("Car with VIN " + args[0] + " not found.")
	}
	historyIer, err := stub.GetHistoryForKey(args[0])

	if err != nil {
		return shim.Error(err.Error())
	}
	// This will only get one previous state, not all states.
	if historyIer.HasNext() {
		modification, err := historyIer.Next()
		if err != nil {
			return shim.Error(err.Error())
		}
		fmt.Println("Returning information about", string(modification.Value))
		return shim.Success([]byte(string(modification.Value)))

	}
	return shim.Success(nil)
}

func (c *CarTrackerChaincode) queryCar(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	if len(args) != 1 {
		return shim.Error("Incorrect number of arguments. Expecting 1")
	}
	carAsBytes, _ := stub.GetState(args[0])
	if carAsBytes == nil {
		return shim.Error("Car with VIN " + args[0] + " not found.")
	}
	return shim.Success(carAsBytes)
}

func (c *CarTrackerChaincode) addRepairWork(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	// Get current repair array and append to it new repair work
	carAsBytes, _ := stub.GetState(args[0])
	if carAsBytes == nil {
		return shim.Error("Car with VIN " + args[0] + " not found.")
	}
	var car Car
	err := json.Unmarshal(carAsBytes, &car)
	if err != nil {
		return shim.Error(err.Error())
	}
	//newRepair := Repair{Date: time.Now().Format, InsuranceCompany: "STAR ASSURANCES", Details: "Replaced windshield due to vandalism."}
	newRepair := Repair{Date: args[1], InsuranceCompany: args[2], Details: args[3]}
	car.Repairs = append(car.Repairs, newRepair)
	carAsBytes, _ = json.Marshal(car)
	stub.PutState(args[0], carAsBytes)
	return shim.Success(nil)
}

func main() {
	ctc := new(CarTrackerChaincode)
	ctc.testMode = false
	err := shim.Start(ctc)
	if err != nil {
		fmt.Printf("Error starting Car Tracker chaincode: %s", err)
	}

}
