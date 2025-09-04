#[test_only]
module recadence::base_agent_tests {
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};

    use recadence::base_agent;

    const TEST_ADMIN_ADDR: address = @0x1111;
    const TEST_USER1_ADDR: address = @0x2222;
    const TEST_USER2_ADDR: address = @0x3333;
    const TEST_UNAUTHORIZED_ADDR: address = @0x9999;

    #[test_only]
    fun setup_test_env() {
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
    }

    #[test_only]
    fun init_aptos_coin() {
        let aptos_framework = account::create_signer_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test_only]
    fun setup_accounts(admin: &signer, user1: &signer, user2: &signer) {
        let admin_addr = signer::address_of(admin);
        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);

        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user1_addr);
        account::create_account_for_test(user2_addr);

        coin::register<AptosCoin>(admin);
        coin::register<AptosCoin>(user1);
        coin::register<AptosCoin>(user2);
    }

    #[test(admin = @0x1111)]
    fun test_initialize_platform(admin: signer) {
        setup_test_env();
        init_aptos_coin();

        base_agent::initialize_platform(&admin);

        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 0, 1);
        assert!(total_active == 0, 2);
    }

    #[test(admin = @0x1111, user1 = @0x2222)]
    fun test_create_base_agent(admin: signer, user1: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user1, &dummy_user);

        base_agent::initialize_platform(&admin);

        let agent_name = b"Test Agent";
        let agent_type = b"test";
        let (base_agent_struct, resource_signer) = base_agent::create_base_agent(
            &user1,
            agent_name,
            agent_type
        );

        base_agent::store_base_agent(&resource_signer, base_agent_struct);
        let resource_addr = signer::address_of(&resource_signer);

        assert!(base_agent::is_agent_active(resource_addr), 1);
        assert!(base_agent::get_agent_creator(resource_addr) == signer::address_of(&user1), 2);
        assert!(base_agent::get_agent_id_by_addr(resource_addr) == 1, 3);

        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(signer::address_of(&user1));
        assert!(active_count == 1, 4);
        assert!(sponsored_count == 1, 5);

        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 1, 6);
        assert!(total_active == 1, 7);
    }

    #[test(admin = @0x1111, user1 = @0x2222)]
    fun test_agent_limit_enforcement(admin: signer, user1: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user1, &dummy_user);

        base_agent::initialize_platform(&admin);

        let i = 0;
        while (i < 10) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            let (base_agent_struct, resource_signer) = base_agent::create_base_agent(
                &user1,
                name,
                b"test"
            );

            base_agent::store_base_agent(&resource_signer, base_agent_struct);
            i = i + 1;
        };

        let (active_count, sponsored_count, _) = base_agent::get_user_agent_info(signer::address_of(&user1));
        assert!(active_count == 10, 1);
        assert!(sponsored_count == 10, 2);
    }

    #[test(admin = @0x1111, user1 = @0x2222)]
    #[expected_failure(abort_code = 1, location = recadence::base_agent)]
    fun test_agent_limit_exceeded_fails(admin: signer, user1: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user1, &dummy_user);

        base_agent::initialize_platform(&admin);

        let i = 0;
        while (i < 10) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            let (base_agent_struct, resource_signer) = base_agent::create_base_agent(
                &user1,
                name,
                b"test"
            );

            base_agent::store_base_agent(&resource_signer, base_agent_struct);
            i = i + 1;
        };

        let (base_agent_struct, resource_signer) = base_agent::create_base_agent(
            &user1,
            b"Agent 11",
            b"test"
        );

        base_agent::store_base_agent(&resource_signer, base_agent_struct);
    }

    #[test(admin = @0x1111, user1 = @0x2222)]
    fun test_agent_pause_resume(admin: signer, user1: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user1, &dummy_user);

        base_agent::initialize_platform(&admin);

        let (base_agent_struct, resource_signer) = base_agent::create_base_agent(
            &user1,
            b"Test Agent",
            b"test"
        );

        let resource_addr = signer::address_of(&resource_signer);
        base_agent::store_base_agent(&resource_signer, base_agent_struct);

        assert!(base_agent::is_agent_active(resource_addr), 1);
        assert!(base_agent::get_agent_state(resource_addr) == 1, 2);

        base_agent::pause_agent_by_addr(resource_addr, &user1);

        assert!(!base_agent::is_agent_active(resource_addr), 3);
        assert!(base_agent::get_agent_state(resource_addr) == 2, 4);

        base_agent::resume_agent_by_addr(resource_addr, &user1);

        assert!(base_agent::is_agent_active(resource_addr), 5);
        assert!(base_agent::get_agent_state(resource_addr) == 1, 6);
    }

    #[test(admin = @0x1111, user1 = @0x2222, unauthorized = @0x9999)]
    #[expected_failure(abort_code = 2, location = recadence::base_agent)]
    fun test_pause_agent_unauthorized_fails(admin: signer, user1: signer, unauthorized: signer) {
        setup_test_env();
        init_aptos_coin();
        setup_accounts(&admin, &user1, &unauthorized);

        base_agent::initialize_platform(&admin);

        let (base_agent_struct, resource_signer) = base_agent::create_base_agent(
            &user1,
            b"Test Agent",
            b"test"
        );

        let resource_addr = signer::address_of(&resource_signer);
        base_agent::store_base_agent(&resource_signer, base_agent_struct);

        base_agent::pause_agent_by_addr(resource_addr, &unauthorized);
    }

    #[test(admin = @0x1111, user1 = @0x2222)]
    fun test_agent_deletion(admin: signer, user1: signer) {
        setup_test_env();
        init_aptos_coin();
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user1, &dummy_user);

        base_agent::initialize_platform(&admin);

        let (base_agent_struct, resource_signer) = base_agent::create_base_agent(
            &user1,
            b"Test Agent",
            b"test"
        );

        let resource_addr = signer::address_of(&resource_signer);
        base_agent::store_base_agent(&resource_signer, base_agent_struct);

        let (_, total_active_before) = base_agent::get_platform_stats();
        assert!(total_active_before == 1, 1);

        base_agent::delete_agent_by_addr(resource_addr, &user1);

        assert!(base_agent::get_agent_state(resource_addr) == 3, 2);

        let (_, total_active_after) = base_agent::get_platform_stats();
        assert!(total_active_after == 0, 3);

        let (active_count, _, _) = base_agent::get_user_agent_info(signer::address_of(&user1));
        assert!(active_count == 0, 4);
    }

    #[test(admin = @0x1111, user1 = @0x2222, user2 = @0x3333)]
    fun test_multi_user_agent_limits(admin: signer, user1: signer, user2: signer) {
        setup_test_env();
        init_aptos_coin();
        setup_accounts(&admin, &user1, &user2);

        base_agent::initialize_platform(&admin);

        let i = 0;
        while (i < 5) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"User1 Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            let (base_agent_struct, resource_signer) = base_agent::create_base_agent(
                &user1,
                name,
                b"test"
            );

            base_agent::store_base_agent(&resource_signer, base_agent_struct);
            i = i + 1;
        };

        let i = 0;
        while (i < 7) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"User2 Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            let (base_agent_struct, resource_signer) = base_agent::create_base_agent(
                &user2,
                name,
                b"test"
            );

            base_agent::store_base_agent(&resource_signer, base_agent_struct);
            i = i + 1;
        };

        let (user1_active, user1_sponsored, _) = base_agent::get_user_agent_info(signer::address_of(&user1));
        let (user2_active, user2_sponsored, _) = base_agent::get_user_agent_info(signer::address_of(&user2));

        assert!(user1_active == 5, 1);
        assert!(user1_sponsored == 5, 2);
        assert!(user2_active == 7, 3);
        assert!(user2_sponsored == 7, 4);

        let (total_created, total_active) = base_agent::get_platform_stats();
        assert!(total_created == 12, 5);
        assert!(total_active == 12, 6);
    }

    #[test(admin = @0x1111)]
    fun test_get_user_agent_ids(admin: signer) {
        setup_test_env();
        init_aptos_coin();
        let user1 = account::create_signer_for_test(@0x2222);
        let dummy_user = account::create_signer_for_test(@0x3333);
        setup_accounts(&admin, &user1, &dummy_user);

        base_agent::initialize_platform(&admin);

        let i = 0;
        while (i < 3) {
            let name = vector::empty<u8>();
            vector::append(&mut name, b"Agent ");
            vector::push_back(&mut name, (48 + i) as u8);

            let (base_agent_struct, resource_signer) = base_agent::create_base_agent(
                &user1,
                name,
                b"test"
            );

            base_agent::store_base_agent(&resource_signer, base_agent_struct);
            i = i + 1;
        };

        let agent_ids = base_agent::get_user_agent_ids(signer::address_of(&user1));

        assert!(vector::length(&agent_ids) == 3, 1);
        assert!(vector::contains(&agent_ids, &1), 2);
        assert!(vector::contains(&agent_ids, &2), 3);
        assert!(vector::contains(&agent_ids, &3), 4);
    }
}
