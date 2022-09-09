// FIXME:
//
// This program needs to output a JSON file with combinatorial test cases.
//
// 1. Create a concrete program that generates the inputs for the _releasePT tests.
//    - [x] Create the combinatorial inputs.
//    - [x] Create the failure cases given a rule set.
//    - [ ] Create success cases given a rule set.
// 2. Clean up the program.
// 3. Generalize the program to handle the creation of more unit tests.
//
use anyhow::Result;
use ethers::abi::{Function, Param, ParamType, StateMutability::Pure, Token};
use serde::{Serialize, Serializer};

fn main() -> Result<()> {
    // Create the full test matrix for the provided test.
    let test_cases = combinations(6)
        .into_iter()
        .map(TestInputReleasePT::from)
        .collect::<Vec<_>>();

    // TODO: Use the entire test matrix.
    let test_cases = test_cases
        .into_iter()
        .map(|t| t.failure_case())
        .filter(|m| m.is_some())
        .collect::<Vec<_>>();

    // Write the test cases to a file.
    let test_cases_json = serde_json::to_string_pretty(&test_cases)?;
    std::fs::create_dir_all("../testdata")?;
    // FIXME: Read the target from an envvar.
    std::fs::write("../testdata/_releasePT.json", test_cases_json)?;

    Ok(())
}

fn serialize<S>(data: &[u8], serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    let s = format!("0x{}", hex::encode(data));
    serializer.serialize_str(&s)
}

#[derive(Serialize)]
struct FailureTestCaseReleasePT {
    #[serde(with = "crate")]
    expected_error: Vec<u8>,
    input: TestInputReleasePT,
}

#[derive(Clone, Serialize)]
struct TestInputReleasePT {
    amount: u128,
    interest: u128,
    shares_per_expiry: u128,
    total_supply: u128,
    underlying: u128,
    user_balance: u128,
}

impl TestInputReleasePT {
    fn failure_case(&self) -> Option<FailureTestCaseReleasePT> {
        if let Some(error_code) = self.error_code() {
            Some(FailureTestCaseReleasePT {
                expected_error: error_code,
                input: self.clone(),
            })
        } else {
            None
        }
    }

    // FIXME: It would be good to add better documentation here explaining the
    // reasoning.
    fn error_code(&self) -> Option<Vec<u8>> {
        // FIXME: Clean this up by creating a lazy_static with all of these errors.
        //
        // bytes public constant assertionError = abi.encodeWithSignature("Panic(uint256)", 0x01);
        // bytes public constant arithmeticError = abi.encodeWithSignature("Panic(uint256)", 0x11);
        // bytes public constant divisionError = abi.encodeWithSignature("Panic(uint256)", 0x12);
        // bytes public constant enumConversionError = abi.encodeWithSignature("Panic(uint256)", 0x21);
        // bytes public constant encodeStorageError = abi.encodeWithSignature("Panic(uint256)", 0x22);
        // bytes public constant popError = abi.encodeWithSignature("Panic(uint256)", 0x31);
        // bytes public constant indexOOBError = abi.encodeWithSignature("Panic(uint256)", 0x32);
        // bytes public constant memOverflowError = abi.encodeWithSignature("Panic(uint256)", 0x41);
        // bytes public constant zeroVarError = abi.encodeWithSignature("Panic(uint256)", 0x51);
        let std_error = Function {
            name: "Panic".to_string(),
            inputs: vec![Param {
                name: "".to_string(),
                kind: ParamType::Uint(256),
                internal_type: None,
            }],
            outputs: vec![],
            constant: None,
            state_mutability: Pure,
        };
        let arithmetic_error = std_error.encode_input(&[Token::Uint(0x11.into())]).unwrap();
        let division_error = std_error.encode_input(&[Token::Uint(0x12.into())]).unwrap();

        if self.underlying == 0 {
            Some(division_error)
        } else if self.interest != 0 && self.shares_per_expiry == 0 {
            Some(arithmetic_error)
        } else if self.total_supply == 0 {
            Some(division_error)
        } else if self.user_balance > self.total_supply {
            Some(arithmetic_error)
        } else {
            None
        }
    }
}

impl From<Vec<u128>> for TestInputReleasePT {
    fn from(vec: Vec<u128>) -> Self {
        assert!(vec.len() == 6);
        Self {
            amount: vec[0],
            interest: vec[1],
            shares_per_expiry: vec[2],
            total_supply: vec[3],
            underlying: vec[4],
            user_balance: vec[5],
        }
    }
}

// TODO: Instead of operating vectors, we can write a Rust macro to create
// combinations of structs.
//
// TODO: This can be extended to handle more input. Currently it just handles
// 0 and 1.
fn combinations(k: usize) -> Vec<Vec<u128>> {
    if k == 1 {
        vec![vec![0], vec![10_u128.pow(18)]]
    } else {
        let mut result = vec![];
        let subcombinations = combinations(k - 1);
        for mut subcombination in subcombinations {
            subcombination.push(0);
            result.push(subcombination.clone());
            subcombination.pop();
            subcombination.push(10_u128.pow(18));
            result.push(subcombination);
        }
        result
    }
}
