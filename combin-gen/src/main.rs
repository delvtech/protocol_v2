// FIXME:
//
// This program needs to output a JSON file with combinatorial test cases.
//
// 1. Create a concrete program that generates the inputs for the _releasePT tests.
//    - [x] Create the combinatorial inputs.
//    - [x] Create the failure cases given a rule set.
//    - [x] Create success cases given a rule set.
// 2. Clean up the program.
// 3. Generalize the program to handle the creation of more unit tests.
//
use anyhow::Result;
use serde::Serialize;

fn main() -> Result<()> {
    // Create the full test matrix for the provided test.
    let test_cases = combinations(6)
        .into_iter()
        .map(TestCaseReleasePT::from)
        .collect::<Vec<_>>();

    // Write the test cases to files.
    // FIXME: Read the target from an envvar.
    std::fs::create_dir_all("../testdata")?;
    let test_cases_json = serde_json::to_string_pretty(&test_cases)?;
    std::fs::write("../testdata/_releasePT.json", test_cases_json)?;

    Ok(())
}

#[derive(Serialize)]
struct TestCaseReleasePT {
    amount: u128,
    interest: u128,
    shares_per_expiry: u128,
    total_supply: u128,
    underlying: u128,
    user_balance: u128,
}

impl From<Vec<u128>> for TestCaseReleasePT {
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
        // FIXME: Mix some fragments into these values.
        vec![vec![0], vec![10_u128.pow(18)], vec![2 * 10_u128.pow(18)]]
    } else {
        let mut result = vec![];
        let subcombinations = combinations(k - 1);
        for mut subcombination in subcombinations {
            subcombination.push(0);
            result.push(subcombination.clone());
            subcombination.pop();
            subcombination.push(10_u128.pow(18));
            result.push(subcombination.clone());
            subcombination.pop();
            subcombination.push(2 * 10_u128.pow(18));
            result.push(subcombination.clone());
        }
        result
    }
}
