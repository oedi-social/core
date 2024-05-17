// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {DataTypes} from './DataTypes.sol';
import {Errors} from './Errors.sol';

/**
 * @title Helpers
 * @author Lens Protocol
 *
 * @notice This is a library that only contains a single function that is used in the hub contract as well as in
 * both the publishing logic and interaction logic libraries.
 */
library Helpers {
    /**
     * @notice This helper function just returns the pointed publication if the passed publication is a mirror,
     * otherwise it returns the passed publication.
     *
     * @param profileId The token ID of the profile that published the given publication.
     * @param pubId The publication ID of the given publication.
     * @param _pubByIdByProfile A pointer to the storage mapping of publications by pubId by profile ID.
     *
     * @return tuple First, the pointed publication's publishing profile ID, second, the pointed publication's ID, and third, the
     * pointed publication's collect module. If the passed publication is not a mirror, this returns the given publication.
     */
    function getPointedIfMirror(
        uint256 profileId,
        uint256 pubId,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile
    )
        internal
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        address collectModule = _pubByIdByProfile[profileId][pubId].collectModule;
        if (collectModule != address(0)) {
            return (profileId, pubId, collectModule);
        } else {
            uint256 pointedTokenId = _pubByIdByProfile[profileId][pubId].profileIdPointed;
            // We validate existence here as an optimization, so validating in calling contracts is unnecessary
            if (pointedTokenId == 0) revert Errors.PublicationDoesNotExist();

            uint256 pointedPubId = _pubByIdByProfile[profileId][pubId].pubIdPointed;

            address pointedCollectModule = _pubByIdByProfile[pointedTokenId][pointedPubId]
                .collectModule;

            return (pointedTokenId, pointedPubId, pointedCollectModule);
        }
    }

    /**
     * @notice This helper function just returns the pointed publication associated with Group, if the passed publication is a mirror,
     * otherwise it returns the passed publication.
     *
     * @param groupId The group ID of the group that has published the given publication.
     * @param profileId The token ID of the profile that published the given publication.
     * @param pubId The publication ID of the given publication.
     * @param _pubByIdByGroupByProfile A pointer to the storage mapping of publications by pubId by group ID by profile ID.
     *
     * @return tuple First, the pointed publication's publishing profile ID, second, the pointed publication's ID, and third, the
     * pointed publication's collect module. If the passed publication is not a mirror, this returns the given publication.
     */
    function getPointedIfGroupMirror(
        uint256 groupId,
        uint256 profileId,
        uint256 pubId,
        mapping(uint256 => mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct)))
            storage _pubByIdByGroupByProfile
    )
        internal
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        address collectModule = _pubByIdByGroupByProfile[profileId][groupId][pubId].collectModule;
        if (collectModule != address(0)) {
            return (profileId, pubId, collectModule);
        } else {
            uint256 pointedTokenId = _pubByIdByGroupByProfile[profileId][groupId][pubId].profileIdPointed;
            // We validate existence here as an optimization, so validating in calling contracts is unnecessary
            if (pointedTokenId == 0) revert Errors.PublicationDoesNotExist();

            uint256 pointedPubId = _pubByIdByGroupByProfile[profileId][groupId][pubId].pubIdPointed;

            address pointedCollectModule = _pubByIdByGroupByProfile[pointedTokenId][groupId][pointedPubId]
                .collectModule;

            return (pointedTokenId, pointedPubId, pointedCollectModule);
        }
    }
}
