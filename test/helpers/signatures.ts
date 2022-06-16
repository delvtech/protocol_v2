import {
  solidityPack,
  keccak256,
  defaultAbiCoder,
  toUtf8Bytes,
} from "ethers/lib/utils";
import { BigNumberish } from "ethers";

export const PERMIT_TYPEHASH = keccak256(
  toUtf8Bytes(
    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
  )
);

export const PERMIT_ALL_TYPEHASH = keccak256(
    toUtf8Bytes(
        "PermitForAll(address owner,address spender,bool _approved,uint256 nonce,uint256 deadline"
    )
);



export function getDigest(
  _: string,
  domainSeparator: string,
  __: string,
  owner: string,
  spender: string,
  value: BigNumberish,
  nonce: BigNumberish,
  deadline: BigNumberish
) {
  return keccak256(
    solidityPack(
      ["bytes1", "bytes1", "bytes32", "bytes32"],
      [
        "0x19",
        "0x01",
        domainSeparator,
        keccak256(
          defaultAbiCoder.encode(
            ["bytes32", "address", "address", "uint256", "uint256", "uint256"],
            [PERMIT_TYPEHASH, owner, spender, value, nonce, deadline]
          )
        ),
      ]
    )
  );
}

export function getDigestAll(
    _: string,
    domainSeparator: string,
    __: string,
    owner: string,
    spender: string,
    _approved: boolean,
    nonce: BigNumberish,
    deadline: BigNumberish
) {
    return keccak256(
        solidityPack(
            ["bytes1", "bytes32", "bytes32"],
            [
                "0x01",
                domainSeparator,
                keccak256(
                    defaultAbiCoder.encode(
                        ["bytes32", "address", "address", "bool", "uint256", "uint256"],
                        [PERMIT_ALL_TYPEHASH, owner, spender, _approved, nonce, deadline]
                    )
                ),
            ]
        )
    );
}
