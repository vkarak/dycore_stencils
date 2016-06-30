#include "gtest/gtest.h"
#include "../Options.hpp"
#include "horizontal_diffusion.h"
#include "../repository.hpp"
#include "../verifier.hpp"
#include "horizontal_diffusion_reference.hpp"

int main(int argc, char** argv)
{

    // Pass command line arguments to googltest
    ::testing::InitGoogleTest(&argc, argv);

    if (argc < 4) {
        printf( "Usage: interface1_<whatever> dimx dimy dimz tsteps \n where args are integer sizes of the data fields and tstep is the number of timesteps to run in a benchmark run\n" );
        return 1;
    }

    for(int i=0; i!=3; ++i) {
        Options::getInstance().m_size[i] = atoi(argv[i+1]);
    }

    if (argc > 4) {
        Options::getInstance().m_size[3] = atoi(argv[4]);
    }
    if (argc == 6) {
        if ((std::string(argv[5]) == "-d"))
            Options::getInstance().m_verify = false;
    }
    return RUN_ALL_TESTS();
}

TEST(HorizontalDiffusion, Test)
{
    unsigned int x = Options::getInstance().m_size[0];
    unsigned int y = Options::getInstance().m_size[1];
    unsigned int z = Options::getInstance().m_size[2];
    unsigned int t = Options::getInstance().m_size[3];
    bool verify = Options::getInstance().m_verify;

    if(t==0) t=1;

    IJKSize domain(x,y,z);
    IJKSize halo(2,2,0);
    repository repo(domain, halo);
    
    repo.make_field("u_in");
    repo.make_field("u_out"); 
    repo.make_field("coeff");

    launch_kernel(repo);

    horizontal_diffusion_reference ref(repo);
    ref.generate_reference();

    repo.update_host("u_out");
    verifier verif(domain, halo, 1e-13);
    ASSERT_TRUE(verif.verify(repo.field_h("u_diff_ref"), repo.field_h("u_out")));
}

