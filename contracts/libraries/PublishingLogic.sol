// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Helpers} from './Helpers.sol';
import {DataTypes} from './DataTypes.sol';
import {Errors} from './Errors.sol';
import {Events} from './Events.sol';
import {Constants} from './Constants.sol';
import {IFollowModule} from '../interfaces/IFollowModule.sol';
import {ICollectModule} from '../interfaces/ICollectModule.sol';
import {IReferenceModule} from '../interfaces/IReferenceModule.sol';

/**
 * @title PublishingLogic
 * @author Lens Protocol
 *
 * @notice This is the library that contains the logic for profile creation & publication.
 *
 * @dev The functions are external, so they are called from the hub via `delegateCall` under the hood. Furthermore,
 * expected events are emitted from this library instead of from the hub to alleviate code size concerns.
 */
library PublishingLogic {
    /**
     * @notice Executes the logic to create a profile with the given parameters to the given address.
     *
     * @param vars The CreateProfileData struct containing the following parameters:
     *      to: The address receiving the profile.
     *      handle: The handle to set for the profile, must be unique and non-empty.
     *      imageURI: The URI to set for the profile image.
     *      followModule: The follow module to use, can be the zero address.
     *      followModuleInitData: The follow module initialization data, if any
     *      followNFTURI: The URI to set for the follow NFT.
     * @param profileId The profile ID to associate with this profile NFT (token ID).
     * @param _profileIdByHandleHash The storage reference to the mapping of profile IDs by handle hash.
     * @param _profileById The storage reference to the mapping of profile structs by IDs.
     * @param _followModuleWhitelisted The storage reference to the mapping of whitelist status by follow module address.
     */
    function createProfile(
        DataTypes.CreateProfileData calldata vars,
        uint256 profileId,
        mapping(bytes32 => uint256) storage _profileIdByHandleHash,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById,
        mapping(address => bool) storage _followModuleWhitelisted
    ) external {
        _validateHandle(vars.handle);

        if (bytes(vars.imageURI).length > Constants.MAX_PROFILE_IMAGE_URI_LENGTH)
            revert Errors.ProfileImageURILengthInvalid();

        bytes32 handleHash = keccak256(bytes(vars.handle));

        if (_profileIdByHandleHash[handleHash] != 0) revert Errors.HandleTaken();

        _profileIdByHandleHash[handleHash] = profileId;
        _profileById[profileId].handle = vars.handle;
        _profileById[profileId].imageURI = vars.imageURI;
        _profileById[profileId].followNFTURI = vars.followNFTURI;

        bytes memory followModuleReturnData;
        if (vars.followModule != address(0)) {
            _profileById[profileId].followModule = vars.followModule;
            followModuleReturnData = _initFollowModule(
                profileId,
                vars.followModule,
                vars.followModuleInitData,
                _followModuleWhitelisted
            );
        }

        _emitProfileCreated(profileId, vars, followModuleReturnData);
    }

    /**
     * @notice Sets the follow module for a given profile.
     *
     * @param profileId The profile ID to set the follow module for.
     * @param followModule The follow module to set for the given profile, if any.
     * @param followModuleInitData The data to pass to the follow module for profile initialization.
     * @param _profile The storage reference to the profile struct associated with the given profile ID.
     * @param _followModuleWhitelisted The storage reference to the mapping of whitelist status by follow module address.
     */
    function setFollowModule(
        uint256 profileId,
        address followModule,
        bytes calldata followModuleInitData,
        DataTypes.ProfileStruct storage _profile,
        mapping(address => bool) storage _followModuleWhitelisted
    ) external {
        if (followModule != _profile.followModule) {
            _profile.followModule = followModule;
        }

        bytes memory followModuleReturnData;
        if (followModule != address(0))
            followModuleReturnData = _initFollowModule(
                profileId,
                followModule,
                followModuleInitData,
                _followModuleWhitelisted
            );
        emit Events.FollowModuleSet(
            profileId,
            followModule,
            followModuleReturnData,
            block.timestamp
        );
    }

    /**
     * @notice Creates a post publication mapped to the given profile.
     *
     * @dev To avoid a stack too deep error, reference parameters are passed in memory rather than calldata.
     *
     * @param profileId The profile ID to associate this publication to.
     * @param contentURI The URI to set for this publication.
     * @param collectModule The collect module to set for this publication.
     * @param collectModuleInitData The data to pass to the collect module for publication initialization.
     * @param referenceModule The reference module to set for this publication, if any.
     * @param referenceModuleInitData The data to pass to the reference module for publication initialization.
     * @param pubId The publication ID to associate with this publication.
     * @param _pubByIdByProfile The storage reference to the mapping of publications by publication ID by profile ID.
     * @param _collectModuleWhitelisted The storage reference to the mapping of whitelist status by collect module address.
     * @param _referenceModuleWhitelisted The storage reference to the mapping of whitelist status by reference module address.
     */
    function createPost(
        uint256 profileId,
        string memory contentURI,
        address collectModule,
        bytes memory collectModuleInitData,
        address referenceModule,
        bytes memory referenceModuleInitData,
        uint256 pubId,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile,
        mapping(address => bool) storage _collectModuleWhitelisted,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) external {
        _pubByIdByProfile[profileId][pubId].contentURI = contentURI;

        // Collect module initialization
        bytes memory collectModuleReturnData = _initPubCollectModule(
            profileId,
            pubId,
            collectModule,
            collectModuleInitData,
            _pubByIdByProfile,
            _collectModuleWhitelisted
        );

        // Reference module initialization
        bytes memory referenceModuleReturnData = _initPubReferenceModule(
            profileId,
            pubId,
            referenceModule,
            referenceModuleInitData,
            _pubByIdByProfile,
            _referenceModuleWhitelisted
        );

        emit Events.PostCreated(
            profileId,
            pubId,
            contentURI,
            collectModule,
            collectModuleReturnData,
            referenceModule,
            referenceModuleReturnData,
            block.timestamp
        );
    }

    /**
    * @notice Creates a post publication mapped to the given group.
    *
    * @dev To avoid a stack too deep error, reference parameters are passed in memory rather than calldata.
    *
    * @param profileId The profile ID publishing this post.
    * @param groupId The group ID to associate this publication to.
    * @param contentURI The URI to set for this publication.
    * @param collectModule The collect module to set for this publication.
    * @param collectModuleInitData The data to pass to the collect module for publication initialization.
    * @param referenceModule The reference module to set for this publication, if any.
    * @param referenceModuleInitData The data to pass to the reference module for publication initialization.
    * @param pubId The publication ID to associate with this publication.
    * @param _pubByIdByGroupByProfile The storage reference to the mapping of group publications by publication ID by group ID by profile ID.
    * @param _collectModuleWhitelisted The storage reference to the mapping of whitelist status by collect module address.
    * @param _referenceModuleWhitelisted The storage reference to the mapping of whitelist status by reference module address.
    */
    function createGroupPost(
        uint256 profileId,
        uint256 groupId,
        string memory contentURI,
        address collectModule,
        bytes memory collectModuleInitData,
        address referenceModule,
        bytes memory referenceModuleInitData,
        uint256 pubId,
        mapping(uint256 => mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct)))
            storage _pubByIdByGroupByProfile,
        mapping(address => bool) storage _collectModuleWhitelisted,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) external {
        _pubByIdByGroupByProfile[profileId][groupId][pubId].contentURI = contentURI;
        _pubByIdByGroupByProfile[profileId][groupId][pubId].pubIdPointed = groupId;

        // Collect module initialization
        bytes memory collectModuleReturnData = _initGroupPubCollectModuleV2(
            profileId,
            groupId,
            pubId,
            collectModule,
            collectModuleInitData,
            _pubByIdByGroupByProfile,
            _collectModuleWhitelisted
        );

        // Reference module initialization
        bytes memory referenceModuleReturnData = _initGroupPubReferenceModule(
            profileId,
            groupId,
            pubId,
            referenceModule,
            referenceModuleInitData,
            _pubByIdByGroupByProfile,
            _referenceModuleWhitelisted
        );

        emit Events.PostPublishedInGroup(
            profileId,
            groupId,
            pubId,
            contentURI,
            collectModule,
            collectModuleReturnData,
            referenceModule,
            referenceModuleReturnData,
            block.timestamp
        );
    }

    /**
    * @notice Creates a group publication mapped to the given profile.
    *
    * @dev To avoid a stack too deep error, reference parameters are passed in memory rather than calldata.
    *
    * @param profileId The profile ID to associate this publication to.
    * @param contentURI The URI to set for this publication.
    * @param collectModule The collect module to set for this publication.
    * @param collectModuleInitData The data to pass to the collect module for publication initialization.
    * @param joinModule The join module to set for this publication.
    * @param joinModuleInitData The data to pass to the join module for publication initialization.
    * @param pubId The publication ID to associate with this publication.
    * @param _groupPubById The storage reference to the mapping of group publications by group ID.
    * @param _collectModuleWhitelisted The storage reference to the mapping of whitelist status by collect module address.
    * @param _joinModuleWhitelisted The storage reference to the mapping of whitelist status by join module address.
    */
    function createGroup(
        uint256 profileId,
        string memory contentURI,
        address collectModule,
        bytes memory collectModuleInitData,
        address joinModule,
        bytes memory joinModuleInitData,
        uint256 pubId,
        mapping(uint256 => DataTypes.GroupStruct)
            storage _groupPubById,
        mapping(address => bool) storage _collectModuleWhitelisted,
        mapping(address => bool) storage _joinModuleWhitelisted
    ) external {
        _groupPubById[pubId].profileId = profileId;
        _groupPubById[pubId].contentURI = contentURI;

        // Collect module initialization
        bytes memory collectModuleReturnData = _initGroupPubCollectModuleV3(
            profileId,
            pubId,
            collectModule,
            collectModuleInitData,
            _groupPubById,
            _collectModuleWhitelisted
        );

        // Join module initialization
        bytes memory joinModuleReturnData = _initPubJoinModule(
            profileId,
            pubId,
            joinModule,
            joinModuleInitData,
            _groupPubById,
            _joinModuleWhitelisted
        );

        emit Events.GroupCreated(
            profileId,
            pubId,
            contentURI,
            collectModule,
            collectModuleReturnData,
            joinModule,
            joinModuleReturnData,
            block.timestamp
        );
    }

    /**
     * @notice Creates a comment publication mapped to the given profile.
     *
     * @dev This function is unique in that it requires many variables, so, unlike the other publishing functions,
     * we need to pass the full CommentData struct in memory to avoid a stack too deep error.
     *
     * @param vars The CommentData struct to use to create the comment.
     * @param pubId The publication ID to associate with this publication.
     * @param _profileById The storage reference to the mapping of profile structs by IDs.
     * @param _pubByIdByProfile The storage reference to the mapping of publications by publication ID by profile ID.
     * @param _collectModuleWhitelisted The storage reference to the mapping of whitelist status by collect module address.
     * @param _referenceModuleWhitelisted The storage reference to the mapping of whitelist status by reference module address.
     */
    function createComment(
        DataTypes.CommentData memory vars,
        uint256 pubId,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile,
        mapping(address => bool) storage _collectModuleWhitelisted,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) external {
        // Validate existence of the pointed publication
        uint256 pubCount = _profileById[vars.profileIdPointed].pubCount;
        if (pubCount < vars.pubIdPointed || vars.pubIdPointed == 0)
            revert Errors.PublicationDoesNotExist();

        // Ensure the pointed publication is not the comment being created
        if (vars.profileId == vars.profileIdPointed && vars.pubIdPointed == pubId)
            revert Errors.CannotCommentOnSelf();

        _pubByIdByProfile[vars.profileId][pubId].contentURI = vars.contentURI;
        _pubByIdByProfile[vars.profileId][pubId].profileIdPointed = vars.profileIdPointed;
        _pubByIdByProfile[vars.profileId][pubId].pubIdPointed = vars.pubIdPointed;

        // Collect Module Initialization
        bytes memory collectModuleReturnData = _initPubCollectModule(
            vars.profileId,
            pubId,
            vars.collectModule,
            vars.collectModuleInitData,
            _pubByIdByProfile,
            _collectModuleWhitelisted
        );

        // Reference module initialization
        bytes memory referenceModuleReturnData = _initPubReferenceModule(
            vars.profileId,
            pubId,
            vars.referenceModule,
            vars.referenceModuleInitData,
            _pubByIdByProfile,
            _referenceModuleWhitelisted
        );

        // Reference module validation
        address refModule = _pubByIdByProfile[vars.profileIdPointed][vars.pubIdPointed]
            .referenceModule;
        if (refModule != address(0)) {
            IReferenceModule(refModule).processComment(
                vars.profileId,
                vars.profileIdPointed,
                vars.pubIdPointed,
                vars.referenceModuleData
            );
        }

        // Prevents a stack too deep error
        _emitCommentCreated(vars, pubId, collectModuleReturnData, referenceModuleReturnData);
    }

    /**
    * @notice Creates a comment publication mapped to the given groupId.
    *
    * @dev This function is unique in that it requires many variables, so, unlike the other publishing functions,
    * we need to pass the full GroupCommentData struct in memory to avoid a stack too deep error.
    *
    * @param vars The GroupCommentData struct to use to create the comment.
    * @param pubId The publication ID to associate with this publication.
    * @param _profileById The storage reference to the mapping of profile structs by IDs.
    * @param _pubByIdByGroupByProfile The storage reference to the mapping of publications by group ID by profile ID.
    * @param _collectModuleWhitelisted The storage reference to the mapping of whitelist status by collect module address.
    * @param _referenceModuleWhitelisted The storage reference to the mapping of whitelist status by reference module address.
    */
    function createGroupComment(
        DataTypes.GroupCommentData memory vars,
        uint256 pubId,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById,
mapping(uint256 => mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct)))
            storage _pubByIdByGroupByProfile,
        mapping(address => bool) storage _collectModuleWhitelisted,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) external {
        if(vars.pubIdPointed == vars.groupId) revert Errors.CannotCommentOnGroup();
        // Validate existence of the pointed publication
        uint256 pubIdPointed = _pubByIdByGroupByProfile[vars.profileIdPointed][vars.groupId][vars.pubIdPointed].pubIdPointed;
        if (pubIdPointed == 0)
            revert Errors.PublicationDoesNotExist();

        // Ensure the pointed publication is not the comment being created
        if (vars.profileId == vars.profileIdPointed && vars.pubIdPointed == pubId)
            revert Errors.CannotCommentOnSelf();

        _pubByIdByGroupByProfile[vars.profileId][vars.groupId][pubId].contentURI = vars.contentURI;
        _pubByIdByGroupByProfile[vars.profileId][vars.groupId][pubId].profileIdPointed = vars.profileIdPointed;
        _pubByIdByGroupByProfile[vars.profileId][vars.groupId][pubId].pubIdPointed = vars.pubIdPointed;

        // Collect Module Initialization
        bytes memory collectModuleReturnData = _initGroupPubCollectModule(
            vars.profileId,
            vars.groupId,
            pubId,
            vars.collectModule,
            vars.collectModuleInitData,
            _pubByIdByGroupByProfile,
            _collectModuleWhitelisted
        );

        // Reference module initialization
        bytes memory referenceModuleReturnData = _initGroupPubReferenceModule(
            vars.profileId,
            vars.groupId,
            pubId,
            vars.referenceModule,
            vars.referenceModuleInitData,
            _pubByIdByGroupByProfile,
            _referenceModuleWhitelisted
        );

        // Reference module validation
        address refModule = _pubByIdByGroupByProfile[vars.profileIdPointed][vars.groupId][vars.pubIdPointed]
            .referenceModule;
        if (refModule != address(0)) {
            IReferenceModule(refModule).processComment(
                vars.profileId,
                vars.profileIdPointed,
                vars.pubIdPointed,
                vars.referenceModuleData
            );
        }

        // Prevents a stack too deep error
        _emitGroupCommentCreated(
            vars,
            pubId,
            collectModuleReturnData,
            referenceModuleReturnData
        );
    }

    /**
     * @notice Creates a mirror publication mapped to the given profile.
     *
     * @param vars The MirrorData struct to use to create the mirror.
     * @param pubId The publication ID to associate with this publication.
     * @param _pubByIdByProfile The storage reference to the mapping of publications by publication ID by profile ID.
     * @param _referenceModuleWhitelisted The storage reference to the mapping of whitelist status by reference module address.
     */
    function createMirror(
        DataTypes.MirrorData memory vars,
        uint256 pubId,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) external {
        (uint256 rootProfileIdPointed, uint256 rootPubIdPointed, ) = Helpers.getPointedIfMirror(
            vars.profileIdPointed,
            vars.pubIdPointed,
            _pubByIdByProfile
        );

        _pubByIdByProfile[vars.profileId][pubId].profileIdPointed = rootProfileIdPointed;
        _pubByIdByProfile[vars.profileId][pubId].pubIdPointed = rootPubIdPointed;

        // Reference module initialization
        bytes memory referenceModuleReturnData = _initPubReferenceModule(
            vars.profileId,
            pubId,
            vars.referenceModule,
            vars.referenceModuleInitData,
            _pubByIdByProfile,
            _referenceModuleWhitelisted
        );

        // Reference module validation
        address refModule = _pubByIdByProfile[rootProfileIdPointed][rootPubIdPointed]
            .referenceModule;
        if (refModule != address(0)) {
            IReferenceModule(refModule).processMirror(
                vars.profileId,
                rootProfileIdPointed,
                rootPubIdPointed,
                vars.referenceModuleData
            );
        }

        emit Events.MirrorCreated(
            vars.profileId,
            pubId,
            rootProfileIdPointed,
            rootPubIdPointed,
            vars.referenceModuleData,
            vars.referenceModule,
            referenceModuleReturnData,
            block.timestamp
        );
    }

    /**
     * @notice Creates a mirror publication mapped to groupId of the given profile.
     *
     * @param vars The GroupMirrorData struct to use to create the mirror.
     * @param pubId The publication ID to associate with this publication.
     * @param _pubByIdByGroupByProfile The storage reference to the mapping of publications by group ID by profile ID.
     * @param _referenceModuleWhitelisted The storage reference to the mapping of whitelist status by reference module address.
     */
    function createGroupMirror(
        DataTypes.GroupMirrorData memory vars,
        uint256 pubId,
        mapping(uint256 => mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct)))
        storage _pubByIdByGroupByProfile,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) external {
        (uint256 rootProfileIdPointed, uint256 rootPubIdPointed, ) = Helpers.getPointedIfGroupMirror(
            vars.groupId,
            vars.profileIdPointed,
            vars.pubIdPointed,
            _pubByIdByGroupByProfile
        );

        _pubByIdByGroupByProfile[vars.profileId][vars.groupId][pubId].profileIdPointed = rootProfileIdPointed;
        _pubByIdByGroupByProfile[vars.profileId][vars.groupId][pubId].pubIdPointed = rootPubIdPointed;

        // Reference module initialization
        bytes memory referenceModuleReturnData = _initGroupPubReferenceModule(
            vars.profileId,
            vars.groupId,
            pubId,
            vars.referenceModule,
            vars.referenceModuleInitData,
            _pubByIdByGroupByProfile,
            _referenceModuleWhitelisted
        );

        // Reference module validation
        address refModule = _pubByIdByGroupByProfile[rootProfileIdPointed][vars.groupId][rootPubIdPointed]
        .referenceModule;
        if (refModule != address(0)) {
            IReferenceModule(refModule).processMirror(
                vars.profileId,
                rootProfileIdPointed,
                rootPubIdPointed,
                vars.referenceModuleData
            );
        }

        emit Events.GroupMirrorCreated(
            vars.profileId,
            pubId,
            rootProfileIdPointed,
            vars.groupId,
            rootPubIdPointed,
            vars.referenceModuleData,
            vars.referenceModule,
            referenceModuleReturnData,
            block.timestamp
        );
    }

    function _initPubCollectModule(
        uint256 profileId,
        uint256 pubId,
        address collectModule,
        bytes memory collectModuleInitData,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile,
        mapping(address => bool) storage _collectModuleWhitelisted
    ) private returns (bytes memory) {
        if (!_collectModuleWhitelisted[collectModule]) revert Errors.CollectModuleNotWhitelisted();
        _pubByIdByProfile[profileId][pubId].collectModule = collectModule;
        return
            ICollectModule(collectModule).initializePublicationCollectModule(
                profileId,
                pubId,
                collectModuleInitData
            );
    }
    function _initGroupPubCollectModule(
        uint256 profileId,
        uint256 groupId,
        uint256 pubId,
        address collectModule,
        bytes memory collectModuleInitData,
        mapping(uint256 => mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct)))
            storage _pubByIdByGroupByProfile,
        mapping(address => bool) storage _collectModuleWhitelisted
    ) private returns (bytes memory) {
        if (!_collectModuleWhitelisted[collectModule]) revert Errors.CollectModuleNotWhitelisted();
        _pubByIdByGroupByProfile[profileId][groupId][pubId].collectModule = collectModule;
        return
            ICollectModule(collectModule).initializePublicationCollectModule(
                profileId,
                pubId,
                collectModuleInitData
            );
    }
    // overloading _initGroupPubCollectModule to support groupPubId & _pubByIdByGroupByProfile as a parameter
    function _initGroupPubCollectModuleV2(
        uint256 profileId,
        uint256 groupId,
        uint256 pubId,
        address collectModule,
        bytes memory collectModuleInitData,
        mapping(uint256 => mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct)))
            storage _pubByIdByGroupByProfile,
        mapping(address => bool) storage _collectModuleWhitelisted
    ) private returns (bytes memory) {
        if (!_collectModuleWhitelisted[collectModule]) revert Errors.CollectModuleNotWhitelisted();
        _pubByIdByGroupByProfile[profileId][groupId][pubId].collectModule = collectModule;
        return
            ICollectModule(collectModule).initializePublicationCollectModule(
                profileId,
                pubId,
                collectModuleInitData
            );
    }
    // overloading _initGroupPubCollectModule to support groupPubId & _groupPubById as a parameter
    function _initGroupPubCollectModuleV3(
        uint256 profileId,
        uint256 groupId,
        address collectModule,
        bytes memory collectModuleInitData,
        mapping(uint256 => DataTypes.GroupStruct)
            storage _groupPubById,
        mapping(address => bool) storage _collectModuleWhitelisted
    ) private returns (bytes memory) {
        if (!_collectModuleWhitelisted[collectModule]) revert Errors.CollectModuleNotWhitelisted();
        _groupPubById[groupId].collectModule = collectModule;
        return
            ICollectModule(collectModule).initializePublicationCollectModule(
                profileId,
                groupId,
                collectModuleInitData
            );
    }

    function _initPubJoinModule(
        uint256 profileId,
        uint256 groupId, // aka pubId
        address joinModule,
        bytes memory joinModuleInitData,
        mapping(uint256 => DataTypes.GroupStruct) storage _groupPubId,
        mapping(address => bool) storage _joinModuleWhitelisted
    ) private returns (bytes memory) {
        if (!_joinModuleWhitelisted[joinModule]) revert Errors.JoinModuleNotWhitelisted();
        _groupPubId[groupId].joinModule = joinModule;
        return
        // using FollowModule interface to initialize join module
            IFollowModule(joinModule).initializeFollowModule(
                groupId, // using groupId as join module should be associated with group not profile
                joinModuleInitData
            );
    }

    function _initPubReferenceModule(
        uint256 profileId,
        uint256 pubId,
        address referenceModule,
        bytes memory referenceModuleInitData,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) private returns (bytes memory) {
        if (referenceModule == address(0)) return new bytes(0);
        if (!_referenceModuleWhitelisted[referenceModule])
            revert Errors.ReferenceModuleNotWhitelisted();
        _pubByIdByProfile[profileId][pubId].referenceModule = referenceModule;
        return
            IReferenceModule(referenceModule).initializeReferenceModule(
                profileId,
                pubId,
                referenceModuleInitData
            );
    }
    function _initGroupPubReferenceModule(
        uint256 profileId,
        uint256 groupId,
        uint256 pubId,
        address referenceModule,
        bytes memory referenceModuleInitData,
        mapping(uint256 => mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct)))
            storage _pubByIdByGroupByProfile,
        mapping(address => bool) storage _referenceModuleWhitelisted
    ) private returns (bytes memory) {
        if (referenceModule == address(0)) return new bytes(0);
        if (!_referenceModuleWhitelisted[referenceModule])
            revert Errors.ReferenceModuleNotWhitelisted();
        _pubByIdByGroupByProfile[profileId][groupId][pubId].referenceModule = referenceModule;
        return
            IReferenceModule(referenceModule).initializeReferenceModule(
                profileId,
                pubId,
                referenceModuleInitData
            );
    }

    function _initFollowModule(
        uint256 profileId,
        address followModule,
        bytes memory followModuleInitData,
        mapping(address => bool) storage _followModuleWhitelisted
    ) private returns (bytes memory) {
        if (!_followModuleWhitelisted[followModule]) revert Errors.FollowModuleNotWhitelisted();
        return IFollowModule(followModule).initializeFollowModule(profileId, followModuleInitData);
    }

    function _emitCommentCreated(
        DataTypes.CommentData memory vars,
        uint256 pubId,
        bytes memory collectModuleReturnData,
        bytes memory referenceModuleReturnData
    ) private {
        emit Events.CommentCreated(
            vars.profileId,
            pubId,
            vars.contentURI,
            vars.profileIdPointed,
            vars.pubIdPointed,
            vars.referenceModuleData,
            vars.collectModule,
            collectModuleReturnData,
            vars.referenceModule,
            referenceModuleReturnData,
            block.timestamp
        );
    }
    function _emitGroupCommentCreated(
        DataTypes.GroupCommentData memory vars,
        uint256 pubId,
        bytes memory collectModuleReturnData,
        bytes memory referenceModuleReturnData
    ) private {
        emit Events.GroupCommentCreated(
            vars.profileId,
            pubId,
            vars.contentURI,
            vars.profileIdPointed,
            vars.pubIdPointed,
            vars.groupId,
            vars.referenceModuleData,
            vars.collectModule,
            collectModuleReturnData,
            vars.referenceModule,
            referenceModuleReturnData,
            block.timestamp
        );
    }

    function _emitProfileCreated(
        uint256 profileId,
        DataTypes.CreateProfileData calldata vars,
        bytes memory followModuleReturnData
    ) internal {
        emit Events.ProfileCreated(
            profileId,
            msg.sender, // Creator is always the msg sender
            vars.to,
            vars.handle,
            vars.imageURI,
            vars.followModule,
            followModuleReturnData,
            vars.followNFTURI,
            block.timestamp
        );
    }

    function _validateHandle(string calldata handle) private pure {
        bytes memory byteHandle = bytes(handle);
        if (byteHandle.length == 0 || byteHandle.length > Constants.MAX_HANDLE_LENGTH)
            revert Errors.HandleLengthInvalid();

        uint256 byteHandleLength = byteHandle.length;
        for (uint256 i = 0; i < byteHandleLength; ) {
            if (
                (byteHandle[i] < '0' ||
                    byteHandle[i] > 'z' ||
                    (byteHandle[i] > '9' && byteHandle[i] < 'a')) &&
                byteHandle[i] != '.' &&
                byteHandle[i] != '-' &&
                byteHandle[i] != '_'
            ) revert Errors.HandleContainsInvalidCharacters();
            unchecked {
                ++i;
            }
        }
    }
}
